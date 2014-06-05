import OpenCL
using ModernGL, GLWindow, GLFW
const cl = OpenCL

wglGetCurrentContext() 	= ccall((:wglGetCurrentContext, "opengl32"), Ptr{Void}, ())
wglGetCurrentDC() 		= ccall((:wglGetCurrentDC, "opengl32"), Ptr{Void}, ())

const window = createWindow([512, 512], "opencl&opengl yeah")

platformid =  	cl.CL_platform_id[0]
platformNum =  	cl.CL_uint[0]
cl.api.clGetPlatformIDs(1, platformid, platformNum)
platform = platformid[1]

const props  = cl.CL_context_properties[
cl.CL_GL_CONTEXT_KHR, wglGetCurrentContext(),
cl.CL_WGL_HDC_KHR, wglGetCurrentDC(),
cl.CL_CONTEXT_PLATFORM , platform, 0]

const devices = cl.devices(:gpu)
const device = devices[1]


# Setup OpenCL
const ctx = cl.Context(props, devices)
const queue = cl.CmdQueue(ctx)
if !device[:has_image_support]
	error("Device $device has no image support. Aborting.")
end

# Setup program parameter
const width = 512 # Also needs changing in qjulia_kernel.cl
const height = 512 # Also needs changing in qjulia_kernel.cl

gl_texture_id = GLuint[0]
glGenTextures(1, gl_texture_id)
gl_texture_id = gl_texture_id[1]
@assert gl_texture_id > 0
glBindTexture(GL_TEXTURE_2D, gl_texture_id)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL);
glBindTexture(GL_TEXTURE_2D, 0)

err_code = Array(cl.CL_int, 1)
const image = cl.api.clCreateFromGLTexture2D(ctx.id, cl.CL_MEM_READ_WRITE, GL_TEXTURE_2D, 0, gl_texture_id, err_code)

if err_code[1] != cl.CL_SUCCESS
    println(err_code[1])
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
const image = cl.Image{cl.RGBA, Float32}(ctx, :w, shape = (width, height, 1, 1, 1, 1)) # OpenCL.jl excpects a shape of dim + nchannels
# Setup OCL buffer
const buffer = cl.Buffer(Float32, ctx, :w, sizeof(Float32) * cl.nchannels(cl.RGBA) * width * height)

function compute()
    cl.call(queue, qjulia_kernel, (width, height), nothing, buffer, μC..., colorC..., ε)

    # err = clEnqueueAcquireGLObjects(ComputeCommands, 1, &ComputeImage, 0, 0, 0);
    # if (err != CL_SUCCESS)
    # {
    #     printf("Failed to acquire GL object! %d\n", err);
    #     return EXIT_FAILURE;
    # }

    # size_t origin[] = { 0, 0, 0 };
    # size_t region[] = { TextureWidth, TextureHeight, 1 };
    # err = clEnqueueCopyBufferToImage(ComputeCommands, ComputeResult, ComputeImage, 
    #                                  0, origin, region, 0, NULL, 0);
    
    # if(err != CL_SUCCESS)
    # {
    #     printf("Failed to copy buffer to image! %d\n", err);
    #     return EXIT_FAILURE;
    # }
    
    # err = clEnqueueReleaseGLObjects(ComputeCommands, 1, &ComputeImage, 0, 0, 0);
    # if (err != CL_SUCCESS)
    # {
    #     printf("Failed to release GL object! %d\n", err);
    #     return EXIT_FAILURE;
    # }
end

# TODO workgroup size

function main()
	compute()
end

main()