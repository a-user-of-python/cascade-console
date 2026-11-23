#!/usr/bin/env python3
"""P1b: mesh convergence of tip deflection (statics only). Prototype."""
import json, numpy as np, scipy.sparse as sp, scipy.sparse.linalg as spla
from fem_prototype import hex8_ke, build_beam, assemble
E, nu = 200_000.0, 0.3
out={}
for h in (2.5, 1.25):
    nodes, elems, (nx,ny,nz), nid = build_beam(100.0,10.0,10.0,h)
    n=len(nodes); Ke,_,_ = hex8_ke(h,E,nu); K=assemble(nodes,elems,Ke)
    fixed=[nid(0,j,k) for j in range(ny+1) for k in range(nz+1)]
    tip=[nid(nx,j,k) for j in range(ny+1) for k in range(nz+1)]
    fd=np.array([3*i+d for i in fixed for d in range(3)])
    free=np.setdiff1d(np.arange(3*n), fd)
    F=np.zeros(3*n)
    for i in tip: F[3*i+2]=-100.0/len(tip)
    Mj=sp.diags(1.0/K.diagonal()).tocsc()
    u=np.zeros(3*n); u[free],info=spla.cg(K[free][:,free],F[free],M=Mj[free][:,free],tol=1e-10,maxiter=10000)
    dz=abs(float(np.mean([u[3*i+2] for i in tip])))
    out[f"h={h}"]={"elements":int(len(elems)),"tip_deflection_mm":dz,
                   "error_vs_euler_bernoulli_pct":100*abs(dz-0.2)/0.2}
print(json.dumps(out,indent=2))
json.dump(out, open("../results/convergence_results.json","w"), indent=2)
