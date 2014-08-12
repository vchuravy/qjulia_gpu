Pkg.update()

pkgs = ["Images", "GLFW"]
for pkg in pkgs
	Pkg.add(pkg)
end

dev_pkgs = [
	"https://github.com/SimonDanisch/GLAbstraction.jl.git"
	"https://github.com/SimonDanisch/ModernGL.jl.git"
	"https://github.com/SimonDanisch/GLWindow.jl.git"
	]

for pkg in dev_pkgs
	Pkg.clone(pkg)
end

Pkg.build()
Pkg.update()