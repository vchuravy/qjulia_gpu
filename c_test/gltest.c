#include <GLFW/glfw3.h>
#include <stdlib.h>
#include <stdio.h>

#include <CL/cl.h>
#include <CL/cl_gl.h>

static void error_callback(int error, const char* description)
{
	fputs(description, stderr);
}
static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
	if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
		glfwSetWindowShouldClose(window, GL_TRUE);
}
int main(void)
{
	GLFWwindow* window;
	glfwSetErrorCallback(error_callback);
	if (!glfwInit())
		exit(EXIT_FAILURE);
	window = glfwCreateWindow(512, 512, "Simple example", NULL, NULL);
	if (!window)
	{
		glfwTerminate();
		exit(EXIT_FAILURE);
	}
	glfwMakeContextCurrent(window);
	glfwSetKeyCallback(window, key_callback);

	int width, height;
	glfwGetFramebufferSize(window, &width, &height);

	glEnable(GL_TEXTURE_2D);
	int texture[1];

	glGenTextures(1, &texture[0]);
    glBindTexture(GL_TEXTURE_2D, texture[0]);   // 2d texture (x and y size)

    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR); // scale linearly when image bigger than texture
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); // scale linearly when image smalled than texture

    // 2d texture, level of detail 0 (normal), 3 components (red, green, blue), x size from image, y size from image, 
    // border 0 (normal), rgb color data, unsigned byte data, and finally the data itself.
    glTexImage2D(GL_TEXTURE_2D, 0, 3, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, NULL);

    // Init OpenCL
    cl_platform_id platform_id = NULL;
    cl_device_id device_id = NULL;   
    cl_uint ret_num_devices;
    cl_uint ret_num_platforms;
    cl_int ret = clGetPlatformIDs(1, &platform_id, &ret_num_platforms);
    ret = clGetDeviceIDs( platform_id, CL_DEVICE_TYPE_DEFAULT, 1, 
            &device_id, &ret_num_devices);

    cl_context_properties properties[] = {
		CL_CONTEXT_PLATFORM, (cl_context_properties)platform_id,
		CL_GL_CONTEXT_KHR, (cl_context_properties)glXGetCurrentContext(),
		CL_GLX_DISPLAY_KHR, (cl_context_properties)glXGetCurrentDisplay(),
	0
	};

    cl_context ctx = clCreateContext(properties, 1, &device_id, NULL, NULL, &ret);
    if(ret != 0)
		printf("Context creation => OpenCL error: %d\n", ret); 
 
    // Create a command queue
    cl_command_queue queue = clCreateCommandQueue(ctx, device_id, 0, &ret);

    //Create Image
	cl_mem image = clCreateFromGLTexture2D(ctx, CL_MEM_READ_WRITE, GL_TEXTURE_2D, 0, texture[0], &ret);
	if(ret != 0)
		printf("Texture creation =>  OpenCL error: %d\n", ret); 

	// Create Buffer RGB * width * height
    cl_mem buffer = clCreateBuffer(ctx, CL_MEM_WRITE_ONLY, 3 * width * height, NULL, &ret);
	if(ret != 0)
		printf("Buffer creation =>  OpenCL error: %d\n", ret); 

	while (!glfwWindowShouldClose(window))
	{
		float ratio;
		ratio = width / (float) height;
		glViewport(0, 0, width, height);
		glClear(GL_COLOR_BUFFER_BIT);
		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();
		glOrtho(-ratio, ratio, -1.f, 1.f, 1.f, -1.f);
		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();
		glRotatef(0.f, 0.f, 0.f, 1.f);
		glBindTexture(GL_TEXTURE_2D, texture[0]);
		glBegin(GL_QUADS);
			glColor3f(1.f, 0.f, 0.f);
			glVertex3f(-1.f, -1.f, 0.f);
			glColor3f(0.f, 1.f, 0.f);
			glVertex3f(-1.f, 1.f, 0.f);
			glColor3f(0.f, 0.f, 1.f);
			glVertex3f(1.f, 1.f, 0.f);
			glColor3f(0.f, 0.f, 1.f);
			glVertex3f(1.f, -1.f, 0.f);
		glEnd();
		glfwSwapBuffers(window);
		glfwPollEvents();
	}

	ret = clFlush(queue);
    ret = clFinish(queue);
    ret = clReleaseMemObject(image);
    ret = clReleaseMemObject(buffer);
    ret = clReleaseCommandQueue(queue);
    ret = clReleaseContext(ctx);

	glfwDestroyWindow(window);
	glfwTerminate();
	exit(EXIT_SUCCESS);
}
