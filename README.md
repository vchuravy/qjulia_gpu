# A Quaterion Julia set implementation in Julia running on the GPU, with OpenCL and OpenGL

Code taken from:

https://developer.apple.com/library/mac/samplecode/OpenCL_RayTraced_Quaternion_Julia-Set_Example/Introduction/Intro.html

For theory and information regarding 4d quaternion julia-sets consult the following:

http://local.wasp.uwa.edu.au/~pbourke/fractals/quatjulia/

http://www.omegafield.net/library/dynamical/quaternion_julia_sets.pdf

http://www.evl.uic.edu/files/pdf/Sandin.RayTracerJuliaSetsbw.pdf

http://www.cs.caltech.edu/~keenan/project_qjulia.html

# Setup:

Currently you will need to use my "fork" of the OpenCL package.

''''bash
rm -rf ~/.julia/v0.3/OpenCL.jl
''''

and in Julia

''''julia
Pkg.clone("git@github.com:vchuravy/OpenCL.jl.git")
Pkg.checkout("OpenCL", "image")
''''

# Status

Currently only the loading and executing of the OpenCL code works.