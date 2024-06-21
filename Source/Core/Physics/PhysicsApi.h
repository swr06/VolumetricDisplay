#pragma once 


#include <glm/glm.hpp>
#include <glm/gtx/matrix_cross_product.hpp> 

#include <iostream>
#include <vector>

#include "PhysicsEntity.h"

namespace Candela {

	class PhysicsHandler {

	public :
		std::vector<PhysicsEntity> EntityList;

		void Initialize();
		void OnUpdate(float AppDt);

	private :

		float m_PhysicsTickAccumulator;
	};

}