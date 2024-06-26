
float sdfoctt(vec3 p, float s)
{
    p = abs(p);
    float m = p.x + p.y + p.z - s;
    vec3 r = 3.0*p - m;
    vec3 o = min(r, 0.0);
    o = max(r*2.0 - o*3.0 + (o.x+o.y+o.z), 0.0);
    return length(p - s*o/(o.x+o.y+o.z));
}

float sdCutSph( in vec3 p2, in float ra, float rb, in float d )
{
    vec2 p = vec2( p2.x, length(p2.yz) );

    float a = (ra*ra - rb*rb + d*d)/(2.0*d);
    float b = sqrt(max(ra*ra-a*a,0.0));
    if( p.x*b-p.y*a > d*max(b-p.y,0.0) )
    {
        return length(p-vec2(a,b));
    }
    else
    {
        return max( (length(p)-ra),
                   -(length(p-vec2(d,0))-rb));
    }
}


// by iq ^

const float epsilon = 0.0002;
const float fov = radians(35.);
const float mandelbulb_power = 8.;
const float view_radius = 20.;
const int mandelbulb_iter_num = 12;
const float camera_distance = 4.;
const float rotation_speed = 1./36.5;

float mandelbulb_sdf(vec3 pos) {
	vec3 z = pos;
	float dr = 1.0;
	float r = 0.0;
	for (int i = 0; i < mandelbulb_iter_num ; i++)
	{
		r = length(z);
		if (r>1.5) break;
		
		// convert to polar coordinates
		float theta = acos(z.z / r);
		float phi = atan(z.y, z.x);

		dr =  pow( r, mandelbulb_power-1.0)*mandelbulb_power*dr + 1.0;
		
		// scale and rotate the point
		float zr = pow( r,mandelbulb_power);
		theta = theta*mandelbulb_power;
		phi = phi*mandelbulb_power;
		
		// convert back to cartesian coordinates
		z = pos + zr*vec3(sin(theta)*cos(phi), sin(phi)*sin(theta), cos(theta));
	}
	return 0.5*log(r)*r/dr;
}