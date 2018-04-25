//////////////////////////////////////////////////////////////////////
// Bezier functions and modules.
//////////////////////////////////////////////////////////////////////

/*
BSD 2-Clause License

Copyright (c) 2017, Revar Desmera
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
	list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
	this list of conditions and the following disclaimer in the documentation
	and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/


include <math.scad>
include <paths.scad>
include <transforms.scad>


// Formulae to calculate points on an N-point bezier curve.
function bez_point(curve,u)=
	(len(curve) <= 1) ?
		curve[0] :
		bez_point(
			[for(i=[0:len(curve)-2]) curve[i]*(1-u)+curve[i+1]*u],
			u
		);


// Takes an array of bezier points and converts it into a 3D polyline.
function bezier_polyline(bezier, splinesteps=16, N=3) = concat(
	[
		for (
			b = [0 : N : len(bezier)-N-1],
			l = [0 : splinesteps-1]
		) let (
			crv = [for (i=[0 : N]) bezier[b+i]],
			u = l / splinesteps
		) bez_point(crv, u)
	],
	[bez_point([for (i=[-(N+1) : -1]) bezier[len(bezier)+i]], 1.0)]
);


// Takes a closed 2D bezier path, and creates a 2D polygon from it.
//   bezier = array of 2D bezier path points
//   splinesteps = number of straight lines to split each bezier segment into
//   N = number of points in each bezier segment.  Cubic = 3
module bezier_polygon(bezier, splinesteps=16, N=3) {
	polypoints=bezier_polyline(bezier, splinesteps, N);
	polygon(points=slice(polypoints, 0, -1));
}


// Generate bezier curve to fillet 2 line segments between 3 points.
// Returns two path points with surrounding cubic (N=3) bezier control points.
function fillet3pts(p0, p1, p2, r) = let(
		v0 = normalize(p0-p1),
		v1 = normalize(p2-p1),
		a = vector3d_angle(v0,v1),
		mr = min(distance(p0,p1), distance(p2,p1))*0.9,
		tr = min(r/tan(a/2), mr),
		tp0 = p1+v0*tr,
		tp1 = p1+v1*tr,
		w=-2.7e-5*a*a + 8.5e-3*a - 3e-3,
		nw=max(0, w),
		cp0 = tp0+nw*(p1-tp0),
		cp1 = tp1+nw*(p1-tp1)
	) [tp0, tp0, cp0, cp1, tp1, tp1];


// Takes a 3D polyline path and fillets it into a 3d cubic (N=3) bezier path.
function fillet_path(pts, fillet) = concat(
	[pts[0], pts[0]],
	(len(pts) < 3)? [] : [
		for (
			p = [1 : len(pts)-2],
			pt = fillet3pts(pts[p-1], pts[p], pts[p+1], fillet)
		) pt
	],
	[pts[len(pts)-1], pts[len(pts)-1]]
);


// Takes a closed 2D bezier and rotates it around the X axis, forming a solid.
//   bezier = array of points for the bezier path to rotate.
//   splinesteps = number of segments to divide each bezier segment into.
//   N = number of points in each bezier segment.  Cubic = 3
// Example:
//   path = [
//     [  0, 10], [ 50,  0], [ 50, 40],
//     [ 95, 40], [100, 40], [100, 45],
//     [ 95, 45], [ 66, 45], [  0, 20],
//     [  0, 12], [  0, 12], [  0, 10],
//     [  0, 10]
//   ];
//   revolve_bezier(path, splinesteps=32, $fn=180);
module revolve_bezier(bezier, splinesteps=16, N=3) {
	yrot(90) rotate_extrude(convexity=10) {
		xrot(180) zrot(-90) bezier_polygon(bezier, splinesteps, N);
	}
}


// Takes a 2D bezier path and closes it to the X axis.
function bezier_close_to_axis(bezier, N=3) =
	let(
		bezend = len(bezier)-1
	) concat(
		[for (i=[0:N-1]) lerp([bezier[0][0], 0], bezier[0], i/N)],
		bezier,
		[for (i=[1:N]) lerp(bezier[bezend], [bezier[bezend][0], 0], i/N)],
		[for (i=[1:N]) lerp([bezier[bezend][0], 0], [bezier[0][0], 0], i/N)]
	);


// Takes a bezier curve and closes it with a matching path that is
// lowered by a given amount towards the X axis.
function bezier_offset(inset, bezier, N=3) =
	let(
		backbez = reverse([ for (pt = bezier) [pt[0], pt[1]-inset] ]),
		bezend = len(bezier)-1
	) concat(
		bezier,
		[for (i=[1:N-1]) lerp(bezier[bezend], backbez[0], i/N)],
		backbez,
		[for (i=[1:N]) lerp(backbez[bezend], bezier[0], i/N)]
	);


// Takes a 2D bezier and rotates it around the X axis, forming a solid.
//   bezier = array of points for the bezier path to rotate.
//   splinesteps = number of segments to divide each bezier segment into.
// Example:
//   path = [ [0, 10], [33, 10], [66, 40], [100, 40] ];
//   revolve_bezier_solid_to_axis(path, splinesteps=32, $fn=72);
module revolve_bezier_solid_to_axis(bezier, splinesteps=16, N=3) {
	revolve_bezier(bezier=bezier_close_to_axis(bezier), splinesteps=splinesteps, N=N);
}


// Takes a 2D bezier and rotates it around the X axis, into a hollow shell.
//   bezier = array of points for the bezier path to rotate.
//   offset = the thickness of the created shell.
//   splinesteps = number of segments to divide each bezier segment into.
// Example:
//   path = [ [0, 10], [33, 10], [66, 40], [100, 40] ];
//   revolve_bezier_offset_shell(path, offset=1, splinesteps=32, $fn=72);
module revolve_bezier_offset_shell(bezier, offset=1, splinesteps=16, N=3) {
	revolve_bezier(bezier=bezier_offset(offset, bezier), splinesteps=splinesteps, N=N);
}


// Extrudes 2D children along a bezier path.
//   bezier = array of points for the bezier path to extrude along.
//   splinesteps = number of segments to divide each bezier segment into.
// Example:
//   path = [ [0, 0, 0], [33, 33, 33], [66, -33, -33], [100, 0, 0] ];
//   extrude_2d_shapes_along_bezier(path, splinesteps=32)
//     circle(r=10, center=true);
module extrude_2d_shapes_along_bezier(bezier, splinesteps=16, N=3) {
	pointslist = slice(bezier_polyline(bezier, splinesteps, N), 0, -1);
	ptcount = len(pointslist);
	for (i = [0 : ptcount-2]) {
		pt1 = pointslist[i];
		pt2 = pointslist[i+1];
		pt0 = i==0? pt1 : pointslist[i-1];
		pt3 = (i>=ptcount-2)? pt2 : pointslist[i+2];
		dist = distance(pt1,pt2);
		v1 = pt2-pt1;
		v0 = (i==0)? v1 : (pt1-pt0);
		v2 = (i==ptcount-2)? v1 : (pt3-pt2);
		az1 = atan2(v1[1], v1[0]);
		alt1 = (len(pt1)<3)? 0 : atan2(v1[2], hypot(v1[1], v1[0]));
		az0 = atan2(v0[1], v0[0]);
		alt0 = (len(pt0)<3)? 0 : atan2(v0[2], hypot(v0[1], v0[0]));
		az2 = atan2(v2[1], v2[0]);
		alt2 = (len(pt2)<3)? 0 : atan2(v2[2], hypot(v2[1], v2[0]));
		translate(pt1) {
			difference() {
				rotate([0, 90-alt1, az1]) {
					translate([0, 0, -1]) {
						linear_extrude(height=dist*3, convexity=10) {
							children();
						}
					}
				}
				rotate([0, 90-(alt0+alt1)/2, (az0+az1)/2]) {
					translate([0, 0, -dist-0.05]) {
						cube(size=[99,99,dist*2], center=true);
					}
				}
				rotate([0, 90-(alt1+alt2)/2, (az1+az2)/2]) {
					translate([0, 0, dist+dist]) {
						cube(size=[99,99,dist*2], center=true);
					}
				}
			}
		}
	}
}


// Takes a closed 2D bezier path, centered on the XY plane, and
// extrudes it perpendicularly along a 3D bezier path, forming a solid.
//   bezier = Array of points of a bezier path, to be extruded.
//   path = Array of points of a bezier path, to extrude along.
//   pathsteps = number of steps to divide each path segment into.
//   bezsteps = number of steps to divide each bezier segment into.
//   bezN = number of points in each extruded bezier segment.  Cubic = 3
//   pathN = number of points in each path bezier segment.  Cubic = 3
// Example:
//   bez = [ [-15, 0], [25, -15], [-5, 10], [0, 10], [5, 10], [10, 5], [15, 0], [10, -5], [5, -10], [0, -10], [-5, -10], [-10, -5], [-15, 0] ];
//   path = [ [0, 0, 0], [33, 33, 33], [66, -33, -33], [100, 0, 0] ];
//   extrude_bezier_along_bezier(bez, path, pathsteps=64, bezsteps=32);
module extrude_bezier_along_bezier(bezier, path, pathsteps=16, bezsteps=16, bezN=3, pathN=3) {
	bez_points = simplify2d_path(bezier_polyline(bezier, bezsteps, bezN));
	path_points = simplify3d_path(path3d(bezier_polyline(path, pathsteps, pathN)));
	extrude_2dpath_along_3dpath(bez_points, path_points);
}


// vim: noexpandtab tabstop=4 shiftwidth=4 softtabstop=4 nowrap
