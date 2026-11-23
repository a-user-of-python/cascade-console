#!/usr/bin/env python3
"""
Cascade Console - Extras prototype P2: OCCT-backed analysis queries.
PROTOTYPE (host, cadquery-ocp / OCCT 7.8.1.1) - same kernel family as shipped.
Checks, each against a closed-form value:
  1. Mass properties of a 40x20x10 mm box (BRepGProp Volume/CoG/inertia)
  2. Interference + clearance between named shapes (BRepAlgoAPI common
     volume + BRepExtrema min distance): overlapping pair and separated pair
  3. Cross-section area at a plane (BRepAlgoAPI_Section + face build)
  4. Draft check primitive: angle between a tapered face normal and pull dir
     (face normal via BRepGProp_Face / surface adaptor)
"""
import json, math
from OCP.BRepPrimAPI import BRepPrimAPI_MakeBox, BRepPrimAPI_MakeCylinder
from OCP.gp import gp_Pnt, gp_Dir, gp_Ax2, gp_Pln, gp_Trsf, gp_Vec
from OCP.BRepAlgoAPI import BRepAlgoAPI_Common, BRepAlgoAPI_Section
from OCP.BRepExtrema import BRepExtrema_DistShapeShape
from OCP.BRepGProp import BRepGProp
from OCP.GProp import GProp_GProps
from OCP.BRepBuilderAPI import BRepBuilderAPI_Transform, BRepBuilderAPI_MakeFace
from OCP.TopAbs import TopAbs_FACE
from OCP.TopExp import TopExp_Explorer
from OCP.TopoDS import TopoDS
from OCP.BRepAdaptor import BRepAdaptor_Surface
from OCP.GeomAbs import GeomAbs_Plane

def vol(shape):
    p = GProp_GProps(); BRepGProp.VolumeProperties_s(shape, p); return p.Mass()
def props(shape):
    p = GProp_GProps(); BRepGProp.VolumeProperties_s(shape, p)
    c = p.CentreOfMass(); m = p.MatrixOfInertia()
    return {"volume_mm3": p.Mass(), "cog": [c.X(), c.Y(), c.Z()],
            "inertia_diag": [m.Value(1,1), m.Value(2,2), m.Value(3,3)]}
def moved(shape, dx, dy, dz):
    t = gp_Trsf(); t.SetTranslation(gp_Vec(dx, dy, dz))
    return BRepBuilderAPI_Transform(shape, t, True).Shape()

out = {}
box = BRepPrimAPI_MakeBox(40.0, 20.0, 10.0).Shape()
bp = props(box)
out["mass_properties_box_40x20x10"] = {
    **bp,
    "analytic": {"volume_mm3": 8000.0, "cog": [20.0, 10.0, 5.0],
                 "inertia_diag": [8000*(20**2+10**2)/12, 8000*(40**2+10**2)/12,
                                  8000*(40**2+20**2)/12]},
    "volume_error_pct": 100*abs(bp["volume_mm3"]-8000.0)/8000.0}
# surface area via GProp surface properties
sp = GProp_GProps(); BRepGProp.SurfaceProperties_s(box, sp)
out["surface_area_box"] = {"mm2": sp.Mass(), "analytic_mm2": 2*(40*20+20*10+40*10)}

# interference: box B shifted +30 in x (overlaps box A by 10 mm in x)
boxB = moved(box, 30.0, 0.0, 0.0)
common = BRepAlgoAPI_Common(box, boxB).Shape()
out["interference_overlap"] = {"common_volume_mm3": vol(common),
                                "analytic_mm3": 10*20*10}
# clearance: box C shifted +50 in x (10 mm gap from A's face at x=40)
boxC = moved(box, 50.0, 0.0, 0.0)
d = BRepExtrema_DistShapeShape(box, boxC); d.Perform()
out["clearance_gap"] = {"min_distance_mm": d.Value(), "analytic_mm": 10.0,
                        "common_volume_mm3": vol(BRepAlgoAPI_Common(box, boxC).Shape())}

# cross-section of a cylinder (r=10, h=30, axis z) at z=12 -> circle area pi r^2
cyl = BRepPrimAPI_MakeCylinder(10.0, 30.0).Shape()
plane_face = BRepBuilderAPI_MakeFace(gp_Pln(gp_Pnt(0,0,12), gp_Dir(0,0,1)), -20, 20, -20, 20).Face()
sec = BRepAlgoAPI_Section(cyl, plane_face).Shape()
# section gives edges; build face from section edges via a planar face on the
# section wire is fiddly - instead measure section by common with thin slab:
slab = moved(BRepPrimAPI_MakeBox(40.0, 40.0, 0.002).Shape(), -20.0, -20.0, 12.0-0.001)
sec_area = vol(BRepAlgoAPI_Common(cyl, slab).Shape())/0.002
out["cross_section_cylinder_at_z12"] = {"area_mm2_slab_method": sec_area,
                                        "analytic_mm2": math.pi*100,
                                        "error_pct": 100*abs(sec_area-math.pi*100)/(math.pi*100),
                                        "method_note": "area = common(cyl, 0.002 mm slab) volume / slab thickness"}

# draft: tapered box via cylinder cone? Use a cone (half-angle atan((10-6)/20))
from OCP.BRepPrimAPI import BRepPrimAPI_MakeCone
cone = BRepPrimAPI_MakeCone(10.0, 6.0, 20.0).Shape()
exp = TopExp_Explorer(cone, TopAbs_FACE); angles=[]
while exp.More():
    f = TopoDS.Face_s(exp.Current())
    ad = BRepAdaptor_Surface(f)
    if ad.GetType() == GeomAbs_Plane:
        pass
    else:
        umin,umax,vmin,vmax = ad.FirstUParameter(), ad.LastUParameter(), ad.FirstVParameter(), ad.LastVParameter()
        pnt = gp_Pnt(); nv = gp_Vec()
        from OCP.BRepGProp import BRepGProp_Face
        gf = BRepGProp_Face(f); gf.Normal((umin+umax)/2, (vmin+vmax)/2, pnt, nv)
        nrm = gp_Dir(nv)
        # draft angle = 90deg - angle between normal and pull dir (0,0,1)... 
        # draft is angle between face and pull dir: asin(|n . pull_perp|)... use:
        cosang = abs(nrm.Dot(gp_Dir(0,0,1)))
        angles.append(90.0 - math.degrees(math.acos(max(-1,min(1,cosang)))))
    exp.Next()
out["draft_cone_side"] = {"draft_angles_deg": angles,
                          "analytic_deg": math.degrees(math.atan((10-6)/20))}
print(json.dumps(out, indent=2))
json.dump(out, open("../results/occt_extras_results.json","w"), indent=2)
