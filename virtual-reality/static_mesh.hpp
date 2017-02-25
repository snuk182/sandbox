#pragma once

#ifndef vr_static_mesh_hpp
#define vr_static_mesh_hpp

#include "renderable.hpp"
#include "bullet_engine.hpp"
#include "bullet_object.hpp"

class StaticMesh : public Renderable
{
	Pose pose;
	float3 scale{ 1, 1, 1 };

	GlMesh mesh;
	Geometry geom;
	Bounds3D bounds;

	BulletObjectVR * physicsComponent{ nullptr };

public:

	StaticMesh() {}

	virtual Pose get_pose() const override { return pose; }
	virtual void set_pose(const Pose & p) override { pose = p; }
	virtual Bounds3D get_bounds() const override { return bounds; }
	virtual float3 get_scale() const override { return scale; }
	virtual void draw() const override { mesh.draw_elements(); }
	virtual void update(const float & dt) override { }

	virtual RaycastResult raycast(const Ray & worldRay) const override
	{
		auto localRay = pose.inverse() * worldRay;
		localRay.origin /= scale;
		localRay.direction /= scale;
		float outT = 0.0f;
		float3 outNormal = { 0, 0, 0 };
		bool hit = intersect_ray_mesh(localRay, geom, &outT, &outNormal);
		return{ hit, outT, outNormal };
	}

	void set_static_mesh(const Geometry & g, const float scale = 1.f)
	{
		geom = g;
		if (scale != 1.f) rescale_geometry(geom, scale);
		bounds = geom.compute_bounds();
		mesh = make_mesh_from_geometry(geom);
	}

	void set_mesh_render_mode(GLenum renderMode)
	{
		if (renderMode != GL_TRIANGLE_STRIP) mesh.set_non_indexed(renderMode);
	}

	void set_physics_component(BulletObjectVR * obj)
	{
		physicsComponent = obj;
	}

	BulletObjectVR * get_physics_component() const
	{
		return physicsComponent;
	}
};

#endif // end vr_static_mesh_hpp
