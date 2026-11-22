// SPDX-License-Identifier: MIT
/*
 * gpu-exec-probe: prove the GPU *executes*, not just that a context exists.
 * Renders a green triangle into an FBO on a given DRM render node through EGL
 * (EGL_PLATFORM_DEVICE / surfaceless), reads a pixel back, and times N draws.
 *
 *   cc -O2 -o gpu-exec-probe gpu-exec-probe.c -lEGL -lGLESv2
 *   ./gpu-exec-probe [/dev/dri/renderD128] [iterations]
 */
#define EGL_EGLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static GLuint sh(GLenum t, const char *src)
{
	GLuint s = glCreateShader(t);
	GLint ok = 0;

	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) { fprintf(stderr, "shader compile failed\n"); exit(2); }
	return s;
}

int main(int argc, char **argv)
{
	const char *node = argc > 1 ? argv[1] : "/dev/dri/renderD128";
	int iters = argc > 2 ? atoi(argv[2]) : 200;
	PFNEGLQUERYDEVICESEXTPROC qdev = (void *)eglGetProcAddress("eglQueryDevicesEXT");
	PFNEGLQUERYDEVICESTRINGEXTPROC qstr = (void *)eglGetProcAddress("eglQueryDeviceStringEXT");
	EGLDeviceEXT devs[16], dev = NULL;
	EGLint n = 0;

	if (!qdev || !qstr || !qdev(16, devs, &n)) { fprintf(stderr, "no EGL device enumeration\n"); return 1; }
	for (int i = 0; i < n; i++) {
		const char *f = qstr(devs[i], EGL_DRM_RENDER_NODE_FILE_EXT);
		if (f && !strcmp(f, node)) dev = devs[i];
	}
	if (!dev) { fprintf(stderr, "render node %s not found among %d EGL devices\n", node, n); return 1; }

	EGLDisplay d = eglGetPlatformDisplay(EGL_PLATFORM_DEVICE_EXT, dev, NULL);
	EGLint maj, min;
	if (!eglInitialize(d, &maj, &min)) { fprintf(stderr, "eglInitialize failed\n"); return 1; }
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint cattr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLContext c = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, cattr);
	if (c == EGL_NO_CONTEXT || !eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, c)) {
		fprintf(stderr, "context failed (EGL error 0x%x)\n", eglGetError()); return 1;
	}
	printf("GL_RENDERER: %s\nGL_VERSION:  %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));

	const int W = 1024, H = 1024;
	GLuint tex, fbo;
	glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { fprintf(stderr, "FBO incomplete\n"); return 1; }

	GLuint p = glCreateProgram();
	glAttachShader(p, sh(GL_VERTEX_SHADER, "attribute vec2 a; void main(){gl_Position=vec4(a,0.0,1.0);}"));
	glAttachShader(p, sh(GL_FRAGMENT_SHADER, "precision mediump float; void main(){gl_FragColor=vec4(0.0,1.0,0.0,1.0);}"));
	glBindAttribLocation(p, 0, "a"); glLinkProgram(p); glUseProgram(p);
	static const GLfloat v[] = { -1, -1, 3, -1, -1, 3 };	/* full-screen triangle */
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, v); glEnableVertexAttribArray(0);
	glViewport(0, 0, W, H);

	struct timespec t0, t1;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	for (int i = 0; i < iters; i++) {
		glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
		glDrawArrays(GL_TRIANGLES, 0, 3);
	}
	unsigned char px[4] = { 0 };
	glReadPixels(W / 2, H / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);	/* implies finish */
	clock_gettime(CLOCK_MONOTONIC, &t1);
	double s = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;

	int pass = px[0] == 0 && px[1] == 255 && px[2] == 0 && glGetError() == GL_NO_ERROR;
	printf("pixel = rgba(%d,%d,%d,%d)\n%d full-screen %dx%d clear+draw in %.3f s = %.1f fps (%.1f Mpix/s)\nRESULT: %s\n",
	       px[0], px[1], px[2], px[3], iters, W, H, s, iters / s, iters * (double)W * H / s / 1e6,
	       pass ? "PASS" : "FAIL");
	return !pass;
}
