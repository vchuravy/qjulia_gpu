import OpenCL
using ModernGL, GLWindow, GLFW, GLAbstraction, Images
const cl = OpenCL

const width = 1024 # Also needs changing in qjulia_kernel.cl
const height = 1024 # Also needs changing in qjulia_kernel.cl

const window = createwindow("QJulia", width, height)

const glVersion = bytestring(glGetString(GL_VERSION))
const glVendor = bytestring(glGetString(GL_VENDOR))
const glRenderer = bytestring(glGetString(GL_RENDERER))

println("Using OpenGL $glVersion on $glRenderer provided by $glVendor")

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

function getDevices(platform)
    props = [getProperties(), (cl.CL_CONTEXT_PLATFORM, platform)]
    parsed_props = cl._parse_properties(props)

    nbytes = cl.Csize_t[0]
    err = cl.api.clGetGLContextInfoKHR(parsed_props, cl.CL_DEVICES_FOR_GL_CONTEXT_KHR, cl.C_NULL, cl.C_NULL, nbytes)
    if (err != cl.CL_SUCCESS)
        error("Failed to query devices! ", err)
    end

    ndevices = div(nbytes[1], sizeof(cl.CL_device_id))
    devices = Array(cl.CL_device_id, ndevices)

    err = cl.api.clGetGLContextInfoKHR(parsed_props, cl.CL_DEVICES_FOR_GL_CONTEXT_KHR, nbytes[1], devices, cl.C_NULL)
    if (err != cl.CL_SUCCESS)
        error("Failed to obtain devices! ", err)
    end

    return [cl.Device(id) for id in devices]
end

# Given a filter function
function getDevice(f :: Function)
    devices = cl.Device[]
    for platform in cl.platforms()
        append!(devices, getDevices(platform))
    end

    devices = filter(f, devices)

    isempty(devices) && error("Could not get any devices")

    gpu_devices = filter(devices) do dev
        dev[:device_type] == :gpu
    end

    isempty(gpu_devices) ? first(devices) : first(gpu_devices)
end

const device = getDevice(dev -> "cl_khr_gl_sharing" in dev[:extensions] && dev[:has_image_support])
const platform = device[:platform]
const clVersion = cl.opencl_version(platform)

println("Using OpenCL $clVersion on $(cl.info(device, :name)) driven by platform $(cl.info(platform, :name))")

const props = [getProperties(), (cl.CL_CONTEXT_PLATFORM, platform)]

# Setup OpenCL
const ctx = cl.Context(device, properties = props)
const queue = cl.CmdQueue(ctx)

# Setup program parameter



gl_texture = Texture(C_NULL, GL_TEXTURE_2D, GL_RGBA8, [width, height], GL_RGBA, GL_UNSIGNED_BYTE)

err_code = Array(cl.CL_int, 1)

if clVersion < v"1.2.0"
	const image = cl.api.clCreateFromGLTexture2D(ctx.id, cl.CL_MEM_READ_WRITE, GL_TEXTURE_2D, 0, gl_texture.id, err_code)
else
	const image = cl.api.clCreateFromGLTexture(ctx.id, cl.CL_MEM_READ_WRITE, GL_TEXTURE_2D, 0, gl_texture.id, err_code)
end
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

    glFinish()
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
    cl.finish(queue)
end

# TODO workgroup size

function main()
	compute()


    const fullscreenQuad = RenderObject([
        :position       => GLBuffer(GLfloat[-1,-1, -1,1, 1,1, 1,-1], 2),
        :indexes        => GLBuffer(GLuint[0, 1, 2,  2, 3, 0], 1, bufferType = GL_ELEMENT_ARRAY_BUFFER),
        :uv             => GLBuffer(GLfloat[0,1,  0,0,  1,0, 1,1], 2),
        :fullscreenTex  => gl_texture
    ], GLProgram("simple"))
    glClearColor(1f0, 1f0, 1f0, 0f0)   
    glViewport(0,0,width, height)
    runner = 0.0f0
    while !GLFW.WindowShouldClose(window)

        μC[1] = float32(sin(runner))
        μC[2] = float32(sin(runner /0.8f0))
        μC[3] = float32(sin(runner /0.6f0))
        μC[4] = float32(sin(runner /0.4f0))

        runner += 0.01f0
        compute()
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
end

main()
