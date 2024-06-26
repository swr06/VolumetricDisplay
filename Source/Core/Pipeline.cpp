#define USE_STACKLESS_TRAVERSAL

#define STRINGIFY(x) (#x)

#include "Pipeline.h"

#include "FpsCamera.h"
#include "GLClasses/Shader.h"
#include "Object.h"
#include "Entity.h"
#include "ModelFileLoader.h" 
#include "ModelRenderer.h"
#include "GLClasses/Fps.h"
#include "GLClasses/Framebuffer.h"
#include "ShaderManager.h"
#include "Utils/Timer.h"


#include "Utils/Random.h"

#include <string>


#include "BVH/BVHConstructor.h"
#include "BVH/Intersector.h"


#include "Utility.h"

#include "Player.h"

#include "../Dependencies/imguizmo/ImGuizmo.h"

#include <implot.h>

// Externs.
int __TotalMeshesRendered = 0;
int __MainViewMeshesRendered = 0;

#ifdef USE_STACKLESS_TRAVERSAL
	Candela::RayIntersector<Candela::BVH::StacklessTraversalNode> Intersector;
#else
	Candela::RayIntersector<Candela::BVH::StackTraversalNode> Intersector;
#endif 

Candela::Player Player;
Candela::FPSCamera& Camera = Player.Camera;

static bool vsync = true;
static Random RNG;

// Options

// Misc 
static float InternalRenderResolution = 1.0f;
static float RoughnessMultiplier = 1.0f;
static bool DoNormalFix = true;
static bool DoFaceCulling = true;

float SpeedMultiplier = 7.0f;


// Timings
float CurrentTime = glfwGetTime();
float Frametime = 0.0f;
float DeltaTime = 0.0f;

// SIM 
float RotSpeed = 1.0f;
int Subframes = 128;
int TemporalFrames = 3;

float ShapeSpeed = 0.5f;
float ShapeThickness = 0.666f;
int CurrentShape = 0;

float AngleBias = 0.0f;
float CurrentBoxAngle = 0.0f;
float CurrentBoxAngleSmooth = 0.0f;


// Render list 
std::vector<Candela::Entity*> EntityRenderList;

// RenderBuffers
GLClasses::Framebuffer RenderBuffers[2] = { GLClasses::Framebuffer(16, 16, {{GL_RGBA16F, GL_RGBA, GL_FLOAT, false, false}}, false, true),GLClasses::Framebuffer(16, 16, {{GL_RGBA16F, GL_RGBA, GL_FLOAT, false, false}}, false, true) };

static double RoundToNearest(double n, double x) {
	return round(n / x) * x;
}

bool WindowResizedThisFrame = false;

class RayTracerApp : public Candela::Application
{
public:

	RayTracerApp()
	{
		m_Width = 800;
		m_Height = 600;
	}

	void OnUserCreate(double ts) override
	{
	
	}

	void OnUserUpdate(double ts) override
	{
		glfwSwapInterval((int)vsync);

		GLFWwindow* window = GetWindow();
		float camera_speed = DeltaTime * 23.0f * ((glfwGetKey(window, GLFW_KEY_TAB) == GLFW_PRESS ? 3.0f : 1.0f));

		Player.OnUpdate(window, DeltaTime, camera_speed * SpeedMultiplier, GetCurrentFrame());
	}

	void OnImguiRender(double ts) override
	{
		ImGuiIO& io = ImGui::GetIO();

		if (ImGui::Begin("Options")) {
			ImGui::Text("Camera Position : %f,  %f,  %f", Camera.GetPosition().x, Camera.GetPosition().y, Camera.GetPosition().z);
			ImGui::Text("Camera Front : %f,  %f,  %f", Camera.GetFront().x, Camera.GetFront().y, Camera.GetFront().z);
			ImGui::Text("Time : %f s", glfwGetTime());
			ImGui::NewLine();
			ImGui::Text("Number of Meshes Rendered (For the main camera view) : %d", __MainViewMeshesRendered);
			ImGui::Text("Total Number of Meshes Rendered : %d", __TotalMeshesRendered);
			ImGui::NewLine();
			ImGui::NewLine();
			ImGui::SliderFloat("Player Speed", &SpeedMultiplier, 0.01f, 24.0f);
			ImGui::NewLine();
			ImGui::SliderFloat("Rotation Speed", &RotSpeed, 0.0f, 4.0f);
			ImGui::SliderFloat("Angle Bias", &AngleBias, -6.282, 6.282);
			ImGui::SliderFloat("Current Angle", &CurrentBoxAngle, CurrentBoxAngle + -6.282, CurrentBoxAngle + 6.282);
			ImGui::SliderInt("Subframes", &Subframes, 1, 384);
			ImGui::SliderInt("Temporal Frames (Reduce this to reduce temporal lag or ghosting)", &TemporalFrames, 1, 128);
			ImGui::NewLine();
			ImGui::SliderInt("Current Shape", &CurrentShape, 0, 3);
			ImGui::SliderFloat("Shape Thickness", &ShapeThickness, 0.1f, 8.0f);
			ImGui::SliderFloat("Shape Rotation Speed", &ShapeSpeed, 0.0f, 4.0f);
			ImGui::NewLine();

			if (ImGui::Button("Reset Angle")) {
				CurrentBoxAngle = 0.0f;
			}
			

		} ImGui::End();

		__TotalMeshesRendered = 0;
		__MainViewMeshesRendered = 0;
	}

	void OnEvent(Candela::Event e) override
	{
		ImGuiIO& io = ImGui::GetIO();

		if (e.type == Candela::EventTypes::MouseMove && GetCursorLocked())
		{
			Camera.UpdateOnMouseMovement(e.mx, e.my);
		}


		if (e.type == Candela::EventTypes::MouseScroll && !ImGui::GetIO().WantCaptureMouse)
		{
			float Sign = e.msy < 0.0f ? 1.0f : -1.0f;
			Camera.SetFov(Camera.GetFov() + 2.0f * Sign);
			Camera.SetFov(glm::clamp(Camera.GetFov(), 1.0f, 89.0f));
		}

		if (e.type == Candela::EventTypes::WindowResize)
		{
			Camera.SetAspect((float)glm::max(e.wx, 1) / (float)glm::max(e.wy, 1));
			WindowResizedThisFrame = true && this->GetCurrentFrame() > 4;
		}

		if (e.type == Candela::EventTypes::KeyPress && e.key == GLFW_KEY_ESCAPE) {
			exit(0);
		}

		if (e.type == Candela::EventTypes::KeyPress && e.key == GLFW_KEY_F1)
		{
			this->SetCursorLocked(!this->GetCursorLocked());
		}

		if (e.type == Candela::EventTypes::KeyPress && e.key == GLFW_KEY_F2 && this->GetCurrentFrame() > 5)
		{
			Candela::ShaderManager::RecompileShaders();
			Intersector.Recompile();
		}

		if (e.type == Candela::EventTypes::KeyPress && e.key == GLFW_KEY_F3 && this->GetCurrentFrame() > 5)
		{
			Candela::ShaderManager::ForceRecompileShaders();
			Intersector.Recompile();
		}

		if (e.type == Candela::EventTypes::KeyPress && e.key == GLFW_KEY_V && this->GetCurrentFrame() > 5)
		{
			vsync = !vsync;
		}

		if (e.type == Candela::EventTypes::MousePress && !ImGui::GetIO().WantCaptureMouse)
		{
		}
	}


};


void RenderEntityList(const std::vector<Candela::Entity*> EntityList, GLClasses::Shader& shader, bool glasspass) {

	int En = 0;
		
	for (auto& e : EntityList) {
		Candela::RenderEntity(*e, shader, Player.CameraFrustum, false, En, glasspass);
		En++;
	}
}


void UnbindEverything() {
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glUseProgram(0);
}




void Candela::StartPipeline()
{
	// Matrices to rotate models whose axis basis is different 
	const glm::mat4 ZOrientMatrix = glm::mat4(glm::vec4(1.0f, 0.0f, 0.0f, 0.0f), glm::vec4(0.0f, 0.0f, 1.0f, 0.0f), glm::vec4(0.0f, 1.0f, 0.0f, 0.0f), glm::vec4(1.0f));
	const glm::mat4 ZOrientMatrixNegative = glm::mat4(glm::vec4(1.0f, 0.0f, 0.0f, 0.0f), glm::vec4(0.0f, 0.0f, 1.0f, 0.0f), glm::vec4(0.0f, -1.0f, 0.0f, 0.0f), glm::vec4(1.0f));

	using namespace BVH;

	// Create App, initialize 
	RayTracerApp app;
	app.Initialize();
	app.SetCursorLocked(true);
	ImPlot::CreateContext();

	// Scene setup 
	Object MainModel;
	Object Cube;
	Object Sphere;
	
	FileLoader::LoadModelFile(&Cube, "Models/cube/scene.gltf");
	FileLoader::LoadModelFile(&MainModel, "Models/cube/scene.gltf");
	FileLoader::LoadModelFile(&Sphere, "Models/ball/scene.gltf");

	// Add objects to intersector
	Intersector.Initialize();

	// Add the objects to the intersector (you could use a vector or similar to make this generic)
	Intersector.AddObject(MainModel);
	Intersector.AddObject(Cube);
	Intersector.AddObject(Sphere);
	Intersector.BufferData(true); // The flag is to tell the intersector to delete the cached cpu data 
	Intersector.GenerateMeshTextureReferences(); // This function is called to generate the texture references for the BVH

	// Create the main model 
	Entity MainModelEntity(&MainModel);



	// Create VBO and VAO for drawing the screen-sized quad.
	GLClasses::VertexBuffer ScreenQuadVBO;
	GLClasses::VertexArray ScreenQuadVAO;

	// Setup screensized quad for rendering
	{
		unsigned long long CurrentFrame = 0;
		float QuadVertices_NDC[] =
		{
			-1.0f,  1.0f,  0.0f, 1.0f, -1.0f, -1.0f,  0.0f, 0.0f,
			 1.0f, -1.0f,  1.0f, 0.0f, -1.0f,  1.0f,  0.0f, 1.0f,
			 1.0f, -1.0f,  1.0f, 0.0f,  1.0f,  1.0f,  1.0f, 1.0f
		};

		ScreenQuadVAO.Bind();
		ScreenQuadVBO.Bind();
		ScreenQuadVBO.BufferData(sizeof(QuadVertices_NDC), QuadVertices_NDC, GL_STATIC_DRAW);
		ScreenQuadVBO.VertexAttribPointer(0, 2, GL_FLOAT, 0, 4 * sizeof(GLfloat), 0);
		ScreenQuadVBO.VertexAttribPointer(1, 2, GL_FLOAT, 0, 4 * sizeof(GLfloat), (void*)(2 * sizeof(GLfloat)));
		ScreenQuadVAO.Unbind();
	}

	// Circuit 
	GLClasses::Texture CircuitBoard;
	CircuitBoard.CreateTexture("Res/board.jpg", false, false);

	// Create Shaders
	ShaderManager::CreateShaders();

	GLClasses::Shader& BasicBlitShader = ShaderManager::GetShader("BASIC_BLIT");
	GLClasses::Shader& RenderShader = ShaderManager::GetShader("RT");

	// Matrices
	glm::mat4 PreviousView;
	glm::mat4 PreviousProjection;
	glm::mat4 View;
	glm::mat4 Projection;
	glm::mat4 InverseView;
	glm::mat4 InverseProjection;


	// GPU Data
	GLuint MatrixSSBO = 0;
	glGenBuffers(1, &MatrixSSBO);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, MatrixSSBO);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(float) * 16 * (1024+1), (void*)0, GL_DYNAMIC_DRAW);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);

	GLuint SmoothMatrixSSBO = 0;
	glGenBuffers(1, &SmoothMatrixSSBO);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, SmoothMatrixSSBO);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(float) * 16 * (1024 + 1), (void*)0, GL_DYNAMIC_DRAW);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
	
	// Motion Blur
	glm::mat4* Matrices = new glm::mat4[1024];
	glm::mat4* SmoothMatrices = new glm::mat4[1024];

	while (!glfwWindowShouldClose(app.GetWindow()))
	{
		// Window is minimized.
		if (glfwGetWindowAttrib(app.GetWindow(), GLFW_ICONIFIED)) {
			app.OnUpdate();
			app.FinishFrame();
			GLClasses::DisplayFrameRate(app.GetWindow(), "Candela ");
			continue;
		}

		InternalRenderResolution = RoundToNearest(InternalRenderResolution, 0.25f);

		// Prepare Intersector
		Intersector.PushEntities(EntityRenderList);
		Intersector.BufferEntities();
		RenderBuffers[0].SetSize(app.GetWidth() * InternalRenderResolution, app.GetHeight() * InternalRenderResolution);
		RenderBuffers[1].SetSize(app.GetWidth() * InternalRenderResolution, app.GetHeight() * InternalRenderResolution);

		auto& CurrentRenderBuffer = RenderBuffers[app.GetCurrentFrame() % 2];
		auto& PrevRenderBuffer = RenderBuffers[int(!bool(app.GetCurrentFrame() % 2))];
		
		PreviousProjection = Camera.GetProjectionMatrix();
		PreviousView = Camera.GetViewMatrix();

		app.OnUpdate(); 
		
		Projection = Camera.GetProjectionMatrix();
		View = Camera.GetViewMatrix();
		InverseProjection = glm::inverse(Camera.GetProjectionMatrix());
		InverseView = glm::inverse(Camera.GetViewMatrix());

		CommonUniforms UniformBuffer = { View, Projection, InverseView, InverseProjection, PreviousProjection, PreviousView, glm::inverse(PreviousProjection), glm::inverse(PreviousView), (int)app.GetCurrentFrame(), glm::vec3(0.0)};

		// Ye 

		// Simulate!

		float Increment = RotSpeed * 2.0f * 3.14f; // 1 rotation / sec

		for (int i = 0; i < Subframes; i++) {
			float Hash = RNG.Float();
			Matrices[i] = glm::rotate(glm::mat4(1.0f), CurrentBoxAngle + AngleBias, glm::vec3(0.0f, 1.0f, 0.0f));
			SmoothMatrices[i] = glm::rotate(glm::mat4(1.0f), CurrentBoxAngleSmooth, glm::vec3(0.5f, 0.95f, 0.6f));
			CurrentBoxAngle += (1.0f / float(Subframes)) * Increment * (1.0f + Hash);
			CurrentBoxAngleSmooth += (1.0f / float(Subframes)) * 3.14f * 2.0f * 0.01f * ShapeSpeed * 0.5f * (1.0f + 0.0f);
		}

		CurrentBoxAngle = glm::mod(CurrentBoxAngle, 6.28f * 256.0f);
		CurrentBoxAngleSmooth = glm::mod(CurrentBoxAngleSmooth, 6.28f * 512.0f);

		glBindBuffer(GL_SHADER_STORAGE_BUFFER, MatrixSSBO);
		glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(float) * 16 * (Subframes), (void*)&Matrices[0], GL_DYNAMIC_DRAW);

		glBindBuffer(GL_SHADER_STORAGE_BUFFER, SmoothMatrixSSBO);
		glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(float) * 16 * (Subframes), (void*)&SmoothMatrices[0], GL_DYNAMIC_DRAW);
		
		// Post processing passes :


		glDisable(GL_CULL_FACE);
		glDisable(GL_DEPTH_TEST);
		glDisable(GL_BLEND);
		glViewport(0, 0, app.GetWidth(), app.GetHeight());

		// Render! 

		CurrentRenderBuffer.Bind();
		RenderShader.Use();

		RenderShader.SetFloat("u_zNear", Camera.GetNearPlane());
		RenderShader.SetFloat("u_zFar", Camera.GetFarPlane());
		RenderShader.SetFloat("u_Time", glfwGetTime());
		RenderShader.SetMatrix4("u_InverseProjection", glm::inverse(Camera.GetProjectionMatrix()));
		RenderShader.SetMatrix4("u_InverseView", glm::inverse(Camera.GetViewMatrix()));
		RenderShader.SetMatrix4("u_PrevProjection", PreviousProjection);
		RenderShader.SetMatrix4("u_PrevView", PreviousView);
		RenderShader.SetVector2f("u_InvRes", 1.0f / glm::vec2(app.GetWidth(), app.GetHeight()));
		RenderShader.SetVector2f("u_Res", glm::vec2(app.GetWidth(), app.GetHeight()));
		RenderShader.SetInteger("u_TemporalFrames", TemporalFrames);
		RenderShader.SetInteger("u_Subframes", Subframes);
		RenderShader.SetInteger("u_SHAPE", CurrentShape);
		RenderShader.SetFloat("u_Thickness", ShapeThickness);

		RenderShader.SetInteger("u_Circuit", 0);
		RenderShader.SetInteger("u_Temporal", 1);
		
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, MatrixSSBO);
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, SmoothMatrixSSBO);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, CircuitBoard.GetTextureID());

		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, PrevRenderBuffer.GetTexture());

		ScreenQuadVAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		ScreenQuadVAO.Unbind();

		CurrentRenderBuffer.Unbind();

		// Blit! 

		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glViewport(0, 0, app.GetWidth(), app.GetHeight());

		BasicBlitShader.Use();
		BasicBlitShader.SetInteger("u_Texture", 0);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, CurrentRenderBuffer.GetTexture());

		ScreenQuadVAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		ScreenQuadVAO.Unbind();

		// Finish 

		glFinish();
		app.FinishFrame();

		CurrentTime = glfwGetTime();
		DeltaTime = CurrentTime - Frametime;
		Frametime = glfwGetTime();

		if (app.GetCurrentFrame() > 4 && WindowResizedThisFrame) {
			WindowResizedThisFrame = false;
		}

		GLClasses::DisplayFrameRate(app.GetWindow(), "Volumetric Display ");
		
		
	}
}

// End.