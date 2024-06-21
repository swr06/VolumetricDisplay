#include "PhysicsApi.h"

namespace Candela {

	void PhysicsHandler::Initialize()
	{
		m_PhysicsTickAccumulator = 0.;
	}

	void PhysicsHandler::OnUpdate(float AppDt)
	{
		float dt = 0.001f;

		m_PhysicsTickAccumulator += AppDt;

		while (m_PhysicsTickAccumulator >= dt) {

			for (auto& e : EntityList) {
			
				e.Position += e.Velocity * dt;
				e.RotationMatrix += dt * glm::matrixCross4(e.Omega) * e.RotationMatrix;
			}


			m_PhysicsTickAccumulator -= dt;
		}

	}
}