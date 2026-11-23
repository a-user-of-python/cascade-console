#!/usr/bin/env python3
"""
Cascade Console - Extras prototype P1: linear FEM core verification.
PROTOTYPE (host, Python/NumPy/SciPy) - not the shipped solver.

Method mirrors the proven CascadeKit facade FEM design (voxel hex8):
- uniform voxel grid, cell kept if centre inside the part
- hex8 trilinear elements, full 2x2x2 Gauss integration, isotropic elasticity
- sparse assembly, PCG solve (Jacobi preconditioner)
Test part: rectangular cantilever beam 100 x 10 x 10 mm, voxel 2.5 mm.
Every headline number is checked against closed-form beam theory.
Units: mm, N, MPa, s.
"""
import json, time
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

# ---------- hex8 element ----------
def hex8_ke(h, E, nu):
    """Stiffness of a cubic hex8 element, side h, 2x2x2 Gauss."""
    C = E/((1+nu)*(1-2*nu)) * np.array([
        [1-nu, nu,   nu,   0, 0, 0],
        [nu,   1-nu, nu,   0, 0, 0],
        [nu,   nu,   1-nu, 0, 0, 0],
        [0,0,0,(1-2*nu)/2,0,0],
        [0,0,0,0,(1-2*nu)/2,0],
        [0,0,0,0,0,(1-2*nu)/2]])
    gp = 1/np.sqrt(3)
    Ke = np.zeros((24,24))
    # node signs in standard hex8 order (bottom CCW from below, then top)
    signs = np.array([[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],
                      [-1,-1, 1],[1,-1, 1],[1,1, 1],[-1,1, 1]], float)
    for a in (-gp,gp):
        for b in (-gp,gp):
            for c in (-gp,gp):
                dN = np.zeros((8,3))
                for i,(sx,sy,sz) in enumerate(signs):
                    dN[i,0] = sx*(1+sy*b)*(1+sz*c)/8 * (2/h)
                    dN[i,1] = (1+sx*a)*sy*(1+sz*c)/8 * (2/h)
                    dN[i,2] = (1+sx*a)*(1+sy*b)*sz/8 * (2/h)
                B = np.zeros((6,24))
                for i in range(8):
                    B[0,3*i]   = dN[i,0]
                    B[1,3*i+1] = dN[i,1]
                    B[2,3*i+2] = dN[i,2]
                    B[3,3*i]   = dN[i,1]; B[3,3*i+1] = dN[i,0]
                    B[4,3*i+1] = dN[i,2]; B[4,3*i+2] = dN[i,1]
                    B[5,3*i]   = dN[i,2]; B[5,3*i+2] = dN[i,0]
                Ke += B.T @ C @ B * (h**3/8)   # detJ * weight(1)
    return Ke, C, signs

def build_beam(L=100.0, W=10.0, H=10.0, h=2.5):
    nx, ny, nz = int(L/h), int(W/h), int(H/h)
    def nid(i,j,k): return (k*(ny+1)+j)*(nx+1)+i
    nodes = np.array([[i*h, j*h, k*h] for k in range(nz+1)
                      for j in range(ny+1) for i in range(nx+1)])
    elems = []
    for k in range(nz):
        for j in range(ny):
            for i in range(nx):
                elems.append([nid(i,j,k), nid(i+1,j,k), nid(i+1,j+1,k), nid(i,j+1,k),
                              nid(i,j,k+1), nid(i+1,j,k+1), nid(i+1,j+1,k+1), nid(i,j+1,k+1)])
    return nodes, np.array(elems), (nx,ny,nz), nid

def assemble(nodes, elems, Ke):
    n = len(nodes); rows=[]; cols=[]; vals=[]
    ke_flat = Ke.ravel()
    for el in elems:
        dofs = np.repeat(el*3,3) + np.tile([0,1,2],8)
        ii,jj = np.meshgrid(dofs,dofs,indexing='ij')
        rows.append(ii.ravel()); cols.append(jj.ravel()); vals.append(ke_flat)
    K = sp.csr_matrix((np.concatenate(vals),
                       (np.concatenate(rows), np.concatenate(cols))), shape=(3*n,3*n))
    return K.tocsc()

def element_vonmises(elems, u, C, signs, h):
    """Per-element centroid von Mises (Gauss point at centre)."""
    gp=0.0; out=np.zeros(len(elems))
    for e,el in enumerate(elems):
        dN=np.zeros((8,3))
        for i,(sx,sy,sz) in enumerate(signs):
            dN[i,0]=sx/8*(2/h); dN[i,1]=sy/8*(2/h); dN[i,2]=sz/8*(2/h)
        B=np.zeros((6,24))
        for i in range(8):
            B[0,3*i]=dN[i,0]; B[1,3*i+1]=dN[i,1]; B[2,3*i+2]=dN[i,2]
            B[3,3*i]=dN[i,1]; B[3,3*i+1]=dN[i,0]
            B[4,3*i+1]=dN[i,2]; B[4,3*i+2]=dN[i,1]
            B[5,3*i]=dN[i,2]; B[5,3*i+2]=dN[i,0]
        ue=np.repeat(el*3,3)+np.tile([0,1,2],8)
        s=C@(B@u[ue])
        out[e]=np.sqrt(0.5*((s[0]-s[1])**2+(s[1]-s[2])**2+(s[2]-s[0])**2
                            +6*(s[3]**2+s[4]**2+s[5]**2)))
    return out

def main():
    t0=time.time()
    E, nu, rho = 200_000.0, 0.3, 7.85e-9   # steel: MPa, -, tonne/mm^3
    L,W,H,h = 100.0,10.0,10.0,2.5
    nodes, elems, (nx,ny,nz), nid = build_beam(L,W,H,h)
    n=len(nodes)
    Ke, C, signs = hex8_ke(h,E,nu)
    K = assemble(nodes, elems, Ke)

    # ---- linear statics: fixed root (x=0), 100 N down (-z) on tip face ----
    P=100.0
    fixed=[nid(0,j,k) for j in range(ny+1) for k in range(nz+1)]
    tip  =[nid(nx,j,k) for j in range(ny+1) for k in range(nz+1)]
    fixed_dofs=np.array([3*i+d for i in fixed for d in range(3)])
    free=np.setdiff1d(np.arange(3*n), fixed_dofs)
    F=np.zeros(3*n)
    for i in tip: F[3*i+2] = -P/len(tip)
    Mjac = sp.diags(1.0/K.diagonal()).tocsc()
    u=np.zeros(3*n)
    u[free], info = spla.cg(K[free][:,free], F[free], M=Mjac[free][:,free],
                            tol=1e-10, maxiter=10000)
    tip_nodes_disp = np.array([np.linalg.norm(u[3*i:3*i+3]) for i in tip])
    # tip deflection = mean z displacement of tip face nodes
    tip_dz = float(np.mean([u[3*i+2] for i in tip]))
    vm = element_vonmises(elems, u, C, signs, h)
    # analytic (Euler-Bernoulli)
    I = W*H**3/12; A=W*H
    delta_eb = P*L**3/(3*E*I)
    sigma_root = (P*L)*(H/2)/I
    res_static = {
        "mesh": {"nodes": int(n), "elements": int(len(elems)), "voxel_mm": h},
        "cg_info": int(info),
        "tip_deflection_mm_fem": abs(tip_dz),
        "tip_deflection_mm_euler_bernoulli": delta_eb,
        "tip_deflection_error_pct": 100*abs(abs(tip_dz)-delta_eb)/delta_eb,
        "max_vonmises_MPa_fem_centroid": float(vm.max()),
        "root_bending_stress_MPa_analytic_outer_fibre": sigma_root,
        "note_vm": "FEM value is per-element CENTROID von Mises on a 2.5 mm voxel "
                   "mesh; the analytic 60 MPa is the outer-fibre peak. Centroid of "
                   "the outermost root element's centroid sits 3.75 mm from the "
                   "neutral axis vs 5 mm at the fibre (0.75x), so a lower FEM "
                   "centroid number (~45 MPa bending-only estimate) is "
                   "expected on this coarse mesh - reported as-is, not scaled.",
    }

    # ---- modal: first bending mode, consistent-ish lumped mass ----
    Me = rho*h**3
    mdiag = np.zeros(3*n)
    for el in elems:
        for i in el:
            for d in range(3): mdiag[3*i+d] += Me/8
    Mm = sp.diags(mdiag).tocsc()
    k_eig = 6
    vals, _ = spla.eigsh(K[free][:,free], M=Mm[free][:,free], k=k_eig,
                         sigma=0.0, which='LM')
    freqs = np.sqrt(np.sort(vals))/(2*np.pi)
    f1_analytic = (1.875104**2/(2*np.pi))*np.sqrt(E*I/(rho*1e9*A*L**4))*1.0
    # rho in tonne/mm^3 -> mass per length = rho*A tonne/mm; E*I in N*mm^2 =
    # tonne*mm/s^2 * mm^2 ... sqrt(EI/(m' L^4)) gives 1/s directly:
    f1_analytic = (1.875104**2/(2*np.pi))*np.sqrt(E*I/((rho*A)*L**4))
    res_modal = {
        "first_6_natural_frequencies_Hz_fem": [float(f) for f in freqs],
        "f1_Hz_analytic_cantilever": float(f1_analytic),
        "f1_error_pct": float(100*abs(freqs[0]-f1_analytic)/f1_analytic),
        "note": "Lumped mass, same mesh/BCs as statics. First two FEM roots are "
                "the degenerate bending pair (y and z planes) - expected for a "
                "square cross-section.",
    }

    # ---- steady-state thermal: conduction along the beam, 100C root, 0C tip --
    # scalar Laplace on the same grid nodes, hex8 conductivity element k=50 W/mK
    kth = 50.0
    ke_t = np.zeros((8,8))
    gp=1/np.sqrt(3)
    for a in (-gp,gp):
        for b in (-gp,gp):
            for c in (-gp,gp):
                dN=np.zeros((8,3))
                for i,(sx,sy,sz) in enumerate(signs):
                    dN[i,0]=sx*(1+sy*b)*(1+sz*c)/8*(2/h)
                    dN[i,1]=(1+sx*a)*sy*(1+sz*c)/8*(2/h)
                    dN[i,2]=(1+sx*a)*(1+sy*b)*sz/8*(2/h)
                ke_t += kth*(dN@dN.T)*(h**3/8)
    rows=[];cols=[];vals=[]
    for el in elems:
        ii,jj=np.meshgrid(el,el,indexing='ij')
        rows.append(ii.ravel()); cols.append(jj.ravel()); vals.append(ke_t.ravel())
    Kt = sp.csr_matrix((np.concatenate(vals),
                        (np.concatenate(rows),np.concatenate(cols))), shape=(n,n)).tocsc()
    tfix = {i:100.0 for i in fixed} | {i:0.0 for i in tip}
    tfree = np.setdiff1d(np.arange(n), list(tfix.keys()))
    T = np.zeros(n)
    for i,v in tfix.items(): T[i]=v
    rhs = -Kt[tfree][:,list(tfix.keys())] @ np.array(list(tfix.values()))
    T[tfree] = spla.spsolve(Kt[tfree][:,tfree], rhs)
    mid = [nid(nx//2,j,k) for j in range(ny+1) for k in range(nz+1)]
    res_thermal = {
        "midpoint_temp_C_fem_mean": float(np.mean([T[i] for i in mid])),
        "midpoint_temp_C_analytic_linear": 50.0,
        "max_abs_deviation_from_linear_C": float(np.max(np.abs(
            T - (100.0*(1.0 - nodes[:,0]/L))))),
        "note": "Uniform cross-section + end Dirichlet faces => exact solution "
                "is linear in x; FEM must reproduce it to solver precision.",
    }

    out = {"prototype": "P1 fem_prototype.py (host Python, NOT shipped code)",
           "part": "cantilever beam 100x10x10 mm, steel E=200000 MPa nu=0.3",
           "statics": res_static, "modal": res_modal, "thermal": res_thermal,
           "wall_time_s": round(time.time()-t0,2)}
    print(json.dumps(out, indent=2))
    with open("../results/fem_prototype_results.json","w") as f:
        json.dump(out, f, indent=2)

if __name__ == "__main__":
    main()
