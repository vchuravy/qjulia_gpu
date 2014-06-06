import OpenCL
using ModernGL, GLFW, GLUtil, Images
const cl = OpenCL

const width = 512 # Also needs changing in qjulia_kernel.cl
const height = 512 # Also needs changing in qjulia_kernel.cl
function initGLWindow()
    GLFW.Init()
    GLFW.WindowHint(GLFW.SAMPLES, 4)
    @osx_only begin
        GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
        GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 2)
        GLFW.WindowHint(GLFW.OPENGL_FORWARD_COMPAT, GL_TRUE)
        GLFW.WindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE)
    end 
    const window = GLFW.CreateWindow(width ,height , "OpenCL OpenGL interop")
    GLFW.MakeContextCurrent(window)
    window
end
const window = initGLWindow()

const device = first(cl.devices(:gpu))
const platform = cl.info(device, :platform)

if !("cl_khr_gl_sharing" in cl.info(device, :extensions)) 
    error("Need extensions cl_khr_gl_sharing")
end

const glLib = @windows? "opengl32" : @linux? "libGL" : ""

@windows? begin
    function getProperties()
        currentContext = ccall(("wglGetCurrentContext", glLib), Ptr{Void}, ())
        currentDC = ccall(("wglGetCurrentDC", glLib), Ptr{Void}, ())

        [(cl.CL_GL_CONTEXT_KHR, currentContext),
        (cl.CL_WGL_HDC_KHR, currentDC)]
    end

end : @linux? begin
    function getProperties()
        currentContext = ccall(("glXGetCurrentContext", glLib), Ptr{Void}, ())
        currentDC = ccall(("glXGetCurrentDisplay", glLib), Ptr{Void}, ())

        [(cl.CL_GL_CONTEXT_KHR, currentContext),
        (cl.CL_GLX_DISPLAY_KHR, currentDC)]
    end

end : error("Can't handle this")

const props = [getProperties(), (cl.CL_CONTEXT_PLATFORM, platform)]


# Setup OpenCL
const ctx = cl.Context(device, properties = props)
const queue = cl.CmdQueue(ctx)

if !device[:has_image_support]
	error("Device $device has no image support. Aborting.")
end

# Setup program parameter



println("creating gl texture")
img = imread("test.png")
gl_texture = Texture(convert(Ptr{Void}, pointer(img.data)), GL_TEXTURE_2D, GL_RGBA8, [width, height], GL_RGBA, GL_UNSIGNED_BYTE)

err_code = Array(cl.CL_int, 1)
const image = cl.api.clCreateFromGLTexture2D(ctx.id, cl.CL_MEM_READ_WRITE, GL_TEXTURE_2D, 0, gl_texture.id, err_code)

if err_code[1] != cl.CL_SUCCESS
    error(err_code[1])
else 
    println("cl texture created from opengl texture successfully")
end

const ε = 0.003f0

const colorT = 0.0f0
const colorA = [0.25f0, 0.45f0, 1.0f0, 1.0f0]
const colorB = [0.25f0, 0.45f0, 1.0f0, 1.0f0]
const colorC = [0.25f0, 0.45f0, 1.0f0, 1.0f0]

const μT = 0.0f0
const μA = [-0.278f0, -0.479f0, 0.0f0, 0.0f0]
const μB = [0.278f0, 0.479f0, 0.0f0, 0.0f0] 
const μC = [-0.278f0, -0.479f0, -0.231f0, 0.235f0]
const kernelsource = open(readall, joinpath(dirname(Base.source_path()), "qjulia_kernel.cl"))
const qjulia_program = cl.Program(ctx, source=kernelsource) |> cl.build!
const qjulia_kernel = cl.Kernel(qjulia_program, "QJuliaKernel")

# Setup clImage and clBuffer
# Original Code CreateComputeResult

# Setup opencl image ref
#const image = cl.Image{cl.RGBA, Float32}(ctx, :w, shape = (width, height, 1, 1, 1, 1)) # OpenCL.jl excpects a shape of dim + nchannels
# Setup OCL buffer
const buffer = cl.Buffer(Float32, ctx, :w, sizeof(Float32) * cl.nchannels(cl.RGBA) * width * height)

function compute()

    cl.call(queue, qjulia_kernel, (width, height), nothing, buffer, μC..., colorC..., ε)
    glFinish()
    println(image)
    err = cl.api.clEnqueueAcquireGLObjects(queue.id, 1, [image], 0, 0, C_NULL)
    if (err != cl.CL_SUCCESS)
        error("Failed to acquire GL object! ", err)
    end
    origin = Csize_t[ 0, 0, 0 ]
    region = Csize_t[width, height, 1 ]
    err = cl.api.clEnqueueCopyBufferToImage(queue.id, buffer.id, image, 
                                     0, origin, region, 0, C_NULL, 0)
    
    if err != cl.CL_SUCCESS
        println("Failed to copy buffer to image! %d\n", err)
    end
    
    err = cl.api.clEnqueueReleaseGLObjects(queue.id, 1, [image], 0, 0, 0)
    if err != cl.CL_SUCCESS
        println("Failed to release GL object! %d\n", err)
    end


end

# TODO workgroup size

function main()
	compute()
end

main()
const fullscreenQuad = RenderObject([
    :position       => GLBuffer(GLfloat[-1,-1, -1,1, 1,1, 1,-1], 2),
    :indexes        => GLBuffer(GLuint[0, 1, 2,  2, 3, 0], 1, bufferType = GL_ELEMENT_ARRAY_BUFFER),
    :uv             => GLBuffer(GLfloat[0,1,  0,0,  1,0, 1,1], 2),
    :fullscreenTex  => gl_texture
], GLProgram("simple"))
glClearColor(1f0, 1f0, 1f0, 0f0)   

while !GLFW.WindowShouldClose(window)

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

    glDisable(GL_DEPTH_TEST)
    programID = fullscreenQuad.vertexArray.program.id
    if programID!= glGetIntegerv(GL_CURRENT_PROGRAM)
        glUseProgram(programID)
    end
    render(fullscreenQuad.uniforms, programID)
    glBindVertexArray(fullscreenQuad.vertexArray.id)
    glDrawElements(GL_TRIANGLES, fullscreenQuad.vertexArray.indexLength, GL_UNSIGNED_INT, GL_NONE)
    # Swap front and back buffers
    GLFW.SwapBuffers(window)

    # Poll for and process events
    GLFW.PollEvents()
end

GLFW.Terminate()