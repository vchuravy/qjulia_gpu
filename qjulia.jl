import OpenCL
using ModernGL, GLFW, GLUtil, Images
const cl = OpenCL

const width = 1024 # Also needs changing in qjulia_kernel.cl
const height = 1024 # Also needs changing in qjulia_kernel.cl

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

const devices = isempty(cl.devices(:gpu)) ? cl.devices() : cl.devices(:gpu)
const device = !isempty(devices) ? first(devices) : error("Could not find a OpenCL device")
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



gl_texture = Texture(C_NULL, GL_TEXTURE_2D, GL_RGBA8, [width, height], GL_RGBA, GL_UNSIGNED_BYTE)

err_code = Array(cl.CL_int, 1)
const image = cl.api.clCreateFromGLTexture2D(ctx.id, cl.CL_MEM_READ_WRITE, GL_TEXTURE_2D, 0, gl_texture.id, err_code)

if err_code[1] != cl.CL_SUCCESS
    error(err_code[1])
else 
    println("cl texture created from opengl texture successfully")
end

const ε = 0.0003f0

const colorT = 0.0f0
const colorA = [0.25f0, 0.45f0, 1.0f0, 1.0f0]
const colorB = [0.9f0, 0.45f0, 0.1f0, 1.0f0]
const colorC = [0.7f0, 0.7f0, 1.0f0, 1.0f0]

const μT = 0.0f0
const μA = [-0.278f0, -0.479f0, 0.2f0, 0.0f0]
const μB = [0.278f0, 0.479f0, 0.0f0, 0.4f0]
const μC = [-0.278f0, -0.03f0, -0.24f0, 0.235f0]
#const μC = [0.285f0, -0.001f0, -0.231f0, 0.235f0]
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
	# Blocking call to compute the context
    cl.call(queue, qjulia_kernel, (width, height), nothing, buffer, μC..., colorC..., ε)

    ret_event = Array(cl.CL_event, 1)

    err = cl.api.clEnqueueAcquireGLObjects(queue.id, cl.cl_uint(1), [image], cl.cl_uint(0), cl.C_NULL, ret_event)
    if (err != cl.CL_SUCCESS)
        error("Failed to acquire GL object! ", err)
    end
    evt_1 = cl.Event(ret_event[1], retain=false)

    origin = Csize_t[ 0, 0, 0 ]
    region = Csize_t[width, height, 1 ]

    err = cl.api.clEnqueueCopyBufferToImage(queue.id, buffer.id, image, 
                                     0, origin, region, cl.cl_uint(1), [evt_1.id], ret_event)
    
    if err != cl.CL_SUCCESS
        println("Failed to copy buffer to image! ", err)
    end
    evt_2 = cl.Event(ret_event[1], retain=false)

    err = cl.api.clEnqueueReleaseGLObjects(queue.id, 1, [image], 1, [evt_2.id], ret_event)
    if err != cl.CL_SUCCESS
        println("Failed to release GL object! ", err)
    end

    evt_3 = cl.Event(ret_event[1], retain=false)
    cl.wait(evt_3)
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
glViewport(0,0,width, height)
while !GLFW.WindowShouldClose(window)

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

    glDisable(GL_DEPTH_TEST)
    programID = fullscreenQuad.vertexArray.program.id
    if programID!= glGetIntegerv(GL_CURRENT_PROGRAM)
        glUseProgram(programID)
    end
    render(fullscreenQuad.uniforms)
    glBindVertexArray(fullscreenQuad.vertexArray.id)
    glDrawElements(GL_TRIANGLES, fullscreenQuad.vertexArray.indexLength, GL_UNSIGNED_INT, GL_NONE)
    # Swap front and back buffers
    GLFW.SwapBuffers(window)

    # Poll for and process events
    GLFW.PollEvents()
end

GLFW.Terminate()