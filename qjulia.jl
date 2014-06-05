# Pkg.checkout("OpenCL", "image")

import OpenCL
const cl = OpenCL

# Setup program parameter

const width = 512 # Also needs changing in qjulia_kernel.cl
const height = 512 # Also needs changing in qjulia_kernel.cl

const ε = 0.003f0

const colorT = 0.0f0
const colorA = [0.25f0, 0.45f0, 1.0f0, 1.0f0]
const colorB = [0.25f0, 0.45f0, 1.0f0, 1.0f0]
const colorC = [0.25f0, 0.45f0, 1.0f0, 1.0f0]

const μT = 0.0f0
const μA = [-0.278f0, -0.479f0, 0.0f0, 0.0f0]
const μB = [0.278f0, 0.479f0, 0.0f0, 0.0f0] 
const μC = [-0.278f0, -0.479f0, -0.231f0, 0.235f0] 

# Setup OpenCL
const device, ctx, queue = cl.create_compute_context()

if !device[:has_image_support]
	error("Device $device has no image support. Aborting.")
end

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
    cl.call(queue, qjulia_kernel, (width, height), nothing, buffer, μC, colorC, ε)


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
	recompute()
end