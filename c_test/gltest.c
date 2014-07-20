#include <GLFW/glfw3.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <CL/cl.h>
#include <CL/cl_gl.h>
#include <CL/cl_gl_ext.h>

static void error_callback(int error, const char* description)
{
	fputs(description, stderr);
}
static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
	if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
		glfwSetWindowShouldClose(window, GL_TRUE);
}

int check_device(cl_device_id device) {
	size_t nbytes;
	clGetDeviceInfo(device, CL_DEVICE_EXTENSIONS, 0, NULL, &nbytes);

	int n_extensions = nbytes / sizeof(char);
	char extensions[n_extensions];

	clGetDeviceInfo(device, CL_DEVICE_EXTENSIONS, nbytes, &extensions, NULL);

	if (strstr(extensions, "cl_khr_gl_sharing") != NULL) {
		return 0;
	} else {
		return -1;
	}
}

// Checks if platform supports the necessary extension.
int check_platform(cl_platform_id platform_id) {
	cl_int ret;  
    cl_uint ndevices;

	ret = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 0, 
            NULL, &ndevices);

	if(ret != 0) {
		printf("Error in check_platform: %d\n", ret); 
    	return(ret);
    }

	cl_device_id devices[ndevices]; 

	ret = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_ALL, ndevices, 
            devices, 0);

	if(ret != 0) {
		printf("Error in check_platform: %d\n", ret); 
    	return(ret);
    }

    for (int i = 0; i < ndevices; ++i)
    {
    	if(check_device(devices[i]) == 0){
    		return(0);
    	}
    }
    return(-1);	
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
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);

    // Init OpenCL
    cl_uint nplatforms;

    cl_int ret = clGetPlatformIDs(0, NULL, &nplatforms);
    if(ret != 0) {
		printf("Could not find OpenCL platforms: %d\n", ret); 
    	exit(ret);
    } else {
    	printf("Found %d platforms \n", nplatforms);
    }

	cl_platform_id platform_ids[nplatforms];
    ret = clGetPlatformIDs(nplatforms, platform_ids, NULL);

    cl_platform_id platform_id;
    for (int i = 0; i < nplatforms; ++i){
    	if(check_platform(platform_ids[i]) == 0) {
    		platform_id = platform_ids[i];
    		break;
    	}
    }	

    // check for extension support
    if(platform_id == NULL) {
    	printf("Did not find any platform that supports the necessary extensions");
    	exit(-1);
    }

    // get pointer to clGetGLContextInfoKHR
	cl_int (*clGetGLContextInfoKHR)(cl_context_properties*, cl_gl_context_info, size_t, void*, size_t*);
	clGetGLContextInfoKHR = clGetExtensionFunctionAddress("clGetGLContextInfoKHR");
	if(clGetGLContextInfoKHR == 0) {
		printf("Could not obtain a function pointer to clGetGLContextInfoKHR"); 
    	exit(-1);
    }

    cl_context_properties properties[] = {
		CL_CONTEXT_PLATFORM, (cl_context_properties)platform_id,
		CL_GL_CONTEXT_KHR, (cl_context_properties)glXGetCurrentContext(),
		CL_GLX_DISPLAY_KHR, (cl_context_properties)glXGetCurrentDisplay(),
	0
	};

	size_t nbytes = NULL;
    ret = clGetGLContextInfoKHR(properties, CL_DEVICES_FOR_GL_CONTEXT_KHR, 0, NULL, &nbytes);
    if(ret != 0) {
		printf("Get Context info => OpenCL error: %d\n", ret); 
    	exit(ret);
    }

    int ndevices = nbytes / sizeof(cl_device_id);
    cl_device_id devices[ndevices];

    ret = clGetGLContextInfoKHR(properties, CL_DEVICES_FOR_GL_CONTEXT_KHR, nbytes, &devices, NULL);
    if(ret != 0) {
		printf("Get Context devices => OpenCL error: %d\n", ret); 
    	exit(ret);
    }

   	cl_device_id device = devices[0];

   	if(check_device(device) == 0){
   		printf("Found device that supports the extensions necessary\n");
   	} else {
   		exit(-1);
   	}

    cl_context ctx = clCreateContext(properties, 1, &device, NULL, NULL, &ret);
    if(ret != 0) {
		printf("Context creation => OpenCL error: %d\n", ret); 
    	exit(ret);
    } else {
    	printf("Context creation successful\n");
    }
 
    // Create a command queue
    cl_command_queue queue = clCreateCommandQueue(ctx, device, 0, &ret);

	if(ret != 0) {
		printf("Queue creation =>  OpenCL error: %d\n", ret); 
		exit(ret);
	} else {
    	printf("Queue creation successful\n");
    }

    //Create Image
	cl_mem image = clCreateFromGLTexture2D(ctx, CL_MEM_READ_WRITE, GL_TEXTURE_2D, 0, texture[0], &ret);
	if(ret != 0) {
		printf("Texture creation =>  OpenCL error: %d\n", ret); 
		exit(ret);
	} else {
    	printf("Texture creation successful\n");
    }

	// Create Buffer RGBA * * width * height
    cl_mem buffer = clCreateBuffer(ctx, CL_MEM_WRITE_ONLY, 4 * width * height * sizeof(GL_UNSIGNED_BYTE), NULL, &ret);
	if(ret != 0) {
		printf("Buffer creation =>  OpenCL error: %d\n", ret); 
		exit(ret);
	} else {
    	printf("Buffer creation successful");
    }

	while (!glfwWindowShouldClose(window))
	{
		glFinish();
		clFinish(queue);

		cl_mem glObjects[] = {image};
		ret = clEnqueueAcquireGLObjects(queue, 1, glObjects, 0, NULL, NULL);
	    if(ret != 0) {
			printf("Acquire GL Objects =>  OpenCL error: %d\n", ret); 
	    	exit(ret);
	    }

		size_t origin[] = { 0, 0, 0 };
		size_t region[] = { width, height, 1 };

	    ret = clEnqueueCopyBufferToImage(queue, buffer, image, 0, origin, region, 0, NULL, NULL);
	    if(ret != 0) {
			printf("Copy Buffer to Image =>  OpenCL error: %d\n", ret); 
	    	exit(ret);
	    }

	    ret = clEnqueueReleaseGLObjects(queue, 1, glObjects, 0, NULL, NULL);
	    if(ret != 0) {
			printf("Copy Buffer to Image =>  OpenCL error: %d\n", ret); 
	    	exit(ret);
	    }
	    clFinish(queue);

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

    ret = clFinish(queue);
    ret = clReleaseMemObject(image);
    ret = clReleaseMemObject(buffer);
    ret = clReleaseCommandQueue(queue);
    ret = clReleaseContext(ctx);

	glfwDestroyWindow(window);
	glfwTerminate();
	exit(EXIT_SUCCESS);
}
