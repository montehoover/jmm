#!/usr/bin/env python


import pyvista as pv


state_to_color = {
    0: 'red', 1: 'yellow', 2: 'green', 3: None, 4: None, 5: None, 6: 'purple'
}


def plot_point(l, scale=1, color='white', opacity=1):
    plotter.add_mesh(
        pv.Sphere(scale*r, points[l]), color=color, opacity=opacity)


def plot_jet(l):
    x = points[l]
    jet = eik.jet[l]
    DT = np.array([jet[1], jet[2], jet[3]])
    plotter.add_mesh(pv.Arrow(x, DT, scale=h), color='white', opacity=0.6)


def plot_cutset(plot_grad=True):
    for (m0, m1), cutedge in eik.shadow_cutset.items():
        t = cutedge.t
        p0, p1 = points[m0], points[m1]
        plotter.add_mesh(
            pv.Cylinder((p0 + p1)/2, p1 - p0, 0.09*r, np.linalg.norm(p1 - p0)),
            opacity=0.5, color='white')
        pt = (1 - t)*p0 + t*p1
        plotter.add_mesh(pv.Sphere(0.2*r, pt), color='white')
        if plot_grad:
            plotter.add_mesh(pv.Arrow(pt, cutedge.n, scale=h),
                             color='white', opacity=0.6)


def plot_update(l0):
    par = eik.get_parent(l0)
    if par.size == 1:
        raise Exception('blah')
    elif par.size == 2:
        p0, p1 = points[par.l[0]], points[par.l[1]]
        plotter.add_mesh(
            pv.Cylinder((p0 + p1)/2, p1 - p0, 0.1*r, np.linalg.norm(p1 - p0)),
            opacity=0.5, color='white')
    else:
        plotter.add_mesh(
            pv.make_tri_mesh(points, np.array(L).reshape(1, 3)),
            opacity=0.5, color='white')
    plotter.add_mesh(
        pv.Sphere(r/3, eik.get_parent(l0).b@points[eik.get_parent(l0).l]),
        color='red', opacity=0.6)


def make_edge(l0, l1):
    assert l0 != l1
    return (min(l0, l1), max(l0, l1))


def get_cut_coef(l0, l1):
    edge = make_edge(l0, l1)
    t = cutset[edge].t
    if edge[0] != l0:
        t = 1 - t
    return t


def get_cut_point(l0, l1):
    t = get_cut_coef(l0, l1)
    x0, x1 = points[l0], points[l1]
    return (1 - t)*x0 + t*x1


def get_verts_and_faces(c, f_offset, verbose=False):
    num_shadow = (eik.state[c] == jmm.State.Shadow.value).sum()
    if num_shadow == 1:
        l0 = next(l for l in c if eik.is_shadow(l))
        l1, l2, l3 = [l for l in c if eik.is_valid(l)]

        t01 = get_cut_coef(l0, l1)
        t02 = get_cut_coef(l0, l2)
        t03 = get_cut_coef(l0, l3)
        if verbose:
            print('- l0 = %d' % (l0,))
            print('- l1 = %d, l2 = %d, l3 = %d' % (l1, l2, l3))
            print('- t01 = %1.3f' % t01)
            print('- t02 = %1.3f' % t02)
            print('- t03 = %1.3f' % t03)

        num_equal_to_zero = (t01 == 0) + (t02 == 0) + (t03 == 0)
        assert num_equal_to_zero != 2

        if num_equal_to_zero == 3:
            return [], []

        v = [get_cut_point(l0, l1), get_cut_point(l0, l2), get_cut_point(l0, l3)]
        f = [[f_offset, f_offset + 1, f_offset + 2]]
        return v, f
    elif num_shadow == 2:
        l0, l1 = [l for l in c if eik.is_shadow(l)]
        l2, l3 = [l for l in c if eik.is_valid(l)]
        t02, t03 = get_cut_coef(l0, l2), get_cut_coef(l0, l3)
        t12, t13 = get_cut_coef(l1, l2), get_cut_coef(l1, l3)
        if verbose:
            print('- l0 = %d, t02 = %1.3f, t03 = %1.3f' % (l0, t02, t03))
            print('- l1 = %d, t12 = %1.3f, t13 = %1.3f' % (l1, t12, t13))

        if t02 == 1 and t12 == 1 and t03 == 1 and t13 == 1:
            return [], []

        if t02 == 1 and t12 == 1:
            v = [points[l2], get_cut_point(l0, l3), get_cut_point(l1, l3)]
            f = [[f_offset, f_offset + 1, f_offset + 2]]
            return v, f

        if t03 == 1 and t13 == 1:
            v = [points[l3], get_cut_point(l0, l2), get_cut_point(l1, l2)]
            f = [[f_offset, f_offset + 1, f_offset + 2]]
            return v, f

        v = [get_cut_point(l0, l2), get_cut_point(l0, l3),
             get_cut_point(l1, l2), get_cut_point(l1, l3)]
        v.append(sum(v)/4)
        f = [[f_offset + 0, f_offset + 1, f_offset + 4],
             [f_offset + 1, f_offset + 3, f_offset + 4],
             [f_offset + 3, f_offset + 2, f_offset + 4],
             [f_offset + 2, f_offset + 0, f_offset + 4]]
        return v, f
    elif num_shadow == 3:
        l0, l1, l2 = [l for l in c if eik.is_shadow(l)]
        l3 = next(l for l in c if eik.is_valid(l))

        t03 = get_cut_coef(l0, l3)
        t13 = get_cut_coef(l1, l3)
        t23 = get_cut_coef(l2, l3)
        if verbose:
            print('- l0 = %d, l1 = %d, l2 = %d' % (l0, l1, l2))
            print('- l3 = %d' % (l3,))
            print('- t03 = %1.3f' % t03)
            print('- t13 = %1.3f' % t13)
            print('- t23 = %1.3f' % t23)

        num_equal_to_one = (t03 == 1) + (t13 == 1) + (t23 == 1)
        assert num_equal_to_one != 2

        if num_equal_to_one == 3:
            return [], []

        v = [get_cut_point(l0, l3), get_cut_point(l1, l3), get_cut_point(l2, l3)]
        f = [[f_offset, f_offset + 1, f_offset + 2]]
        return v, f
    else:
        assert False


if __name__ == '__main__':
    indsrc = 36

    tet_mesh = 'L/L.1.vtk'
    surf_mesh = pv.read('L.obj')

    grid = pv.read(tet_mesh)
    points = grid.points.copy().astype(np.float64)
    cells = grid.cells.reshape(-1, 5)[:, 1:].copy().astype(np.uintp)

    mesh = jmm.Mesh3(verts, cells)

    eik = jmm.Eik3(mesh)
    eik.add_trial(indsrc, 0)
    eik.solve()

    r = 0.05

    plotter = pvqt.BackgroundPlotter()
    plotter.background_color = (0.6, 0.6, 0.6)
    plotter.add_mesh(surf_mesh, 'r', 'wireframe')

    plot_point(indsrc, color='red', scale=0.6, opacity=0.5)

    for l in range(points.shape[0]):
        if eik.state[l] == 0:
            continue
        color = state_to_color[eik.state[l]]
        plot_point(l, scale=0.3, color=color)

    h = 0.1

    plot_cutset(False)

    # plot_update(l0)

    cutset = eik.shadow_cutset

    # First, find the tetrahedra bracketing dZ

    Lc = np.where(
        (eik.state[cells] == jmm.State.Valid.value).any(1) &
        (eik.state[cells] == jmm.State.Shadow.value).any(1)
    )[0]

    verbose = False

    V, F = [], []
    for i, c in enumerate(cells[Lc]):
        if verbose:
            print(i, c)
        v, f = get_verts_and_faces(c, f_offset=len(V), verbose=verbose)
        V.extend(v)
        F.extend(f)
        if verbose:
            print()

    if V:
        V = np.array(V)
        F = np.array(F, dtype=int)
        plotter.add_mesh(
            pv.make_tri_mesh(V, F),
            color='purple', opacity=0.5, show_edges=True)