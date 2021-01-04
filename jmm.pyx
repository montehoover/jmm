# cython: embedsignature=True
# cython: language_level=3

import numpy as np

import array

from cython cimport Py_buffer

from libc.stdlib cimport free, malloc
from libc.string cimport memcpy

from enum import Enum

ctypedef bint bool

cdef extern from "def.h":
    ctypedef double dbl
    cdef enum state:
        FAR
        TRIAL
        VALID
        BOUNDARY
        NEW_VALID
    cdef enum stype:
        CONSTANT
        NUM_STYPE
    cdef enum error:
        SUCCESS
        BAD_ARGUMENT

cdef extern from "immintrin.h":
    ctypedef double __m256d

cdef extern from "vec.h":
    ctypedef struct dvec3:
        dbl data[4]
        __m256d packed
    ctypedef struct dvec4:
        dbl data[4]
        __m256d packed

cdef extern from "jet.h":
    ctypedef struct jet3:
        dbl f
        dbl fx
        dbl fy
        dbl fz

cdef extern from "bb.h":
    void bb3tet_interp3(const dbl f[4], const dbl Df[4][3], const dbl x[4][3], dbl c[20])
    dbl bb3tet(const dbl c[20], const dbl b[4])
    dbl dbb3tet(const dbl c[20], const dbl b[4], const dbl a[4])
    dbl d2bb3tet(const dbl c[20], const dbl b[4], const dbl a[2][4])

cdef extern from "dial.h":
    cdef struct dial3:
        pass
    void dial3_alloc(dial3 **dial)
    error dial3_init(dial3 *dial, stype stype, const int *shape, dbl h)
    void dial3_deinit(dial3 *dial)
    void dial3_dealloc(dial3 **dial)
    void dial3_add_point_source(dial3 *dial, const int *ind0, dbl T)
    void dial3_add_boundary_points(dial3 *dial, const int *inds, size_t n)
    bool dial3_step(dial3 *dial)
    void dial3_solve(dial3 *dial)
    dbl dial3_get_T(const dial3 *dial, int l)
    void dial3_get_grad_T(const dial3 *dial, int l, dbl *grad_T)
    dbl *dial3_get_Toff_ptr(const dial3 *dial)
    dbl *dial3_get_xsrc_ptr(const dial3 *dial)
    state *dial3_get_state_ptr(const dial3 *dial)

cdef extern from "mesh3.h":
    struct mesh3:
        pass
    void mesh3_alloc(mesh3 **mesh)
    void mesh3_dealloc(mesh3 **mesh)
    void mesh3_init(mesh3 *mesh,
                    dbl *verts, size_t nverts,
                    size_t *cells, size_t ncells)
    void mesh3_deinit(mesh3 *mesh)
    size_t mesh3_nverts(const mesh3 *mesh)
    int mesh3_nvc(const mesh3 *mesh, size_t i)
    void mesh3_vc(const mesh3 *mesh, size_t i, size_t *vc)
    int mesh3_nvv(const mesh3 *mesh, size_t i)
    void mesh3_vv(const mesh3 *mesh, size_t i, size_t *vv)
    int mesh3_ncc(const mesh3 *mesh, size_t i)
    void mesh3_cc(const mesh3 *mesh, size_t i, size_t *cc)
    void mesh3_cv(const mesh3 *mesh, size_t i, size_t *cv)
    int mesh3_nec(const mesh3 *mesh, size_t i, size_t j)
    void mesh3_ec(const mesh3 *mesh, size_t i, size_t j, size_t *ec)
    bool mesh3_bdc(const mesh3 *mesh, size_t i)

cdef extern from "eik3.h":
    cdef struct eik3:
        pass
    void eik3_alloc(eik3 **eik)
    void eik3_dealloc(eik3 **eik)
    void eik3_init(eik3 *eik, const mesh3 *mesh)
    void eik3_deinit(eik3 *eik)
    size_t eik3_peek(const eik3 *eik)
    size_t eik3_step(eik3 *eik)
    void eik3_solve(eik3 *eik)
    void eik3_add_trial(eik3 *eik, size_t ind, jet3 jet)
    void eik3_add_valid(eik3 *eik, size_t ind, jet3 jet)
    const mesh3 *eik3_get_mesh(const eik3 *eik)
    bool eik3_is_far(const eik3 *eik, size_t ind)
    bool eik3_is_trial(const eik3 *eik, size_t ind)
    bool eik3_is_valid(const eik3 *eik, size_t ind)
    jet3 *eik3_get_jet_ptr(const eik3 *eik)
    state *eik3_get_state_ptr(const eik3 *eik)
    int eik3_get_num_full_updates(const eik3 *eik)
    int *eik3_get_full_update_ptr(const eik3 *eik)

cdef extern from "utetra.h":
    cdef struct utetra:
        pass
    void utetra_alloc(utetra **cf)
    void utetra_dealloc(utetra **cf)
    void utetra_init_from_eik3(utetra *cf, const eik3 *eik,
                              size_t l, size_t l0, size_t l1, size_t l2)
    void utetra_init(utetra *cf, const dbl x[3], const dbl Xt[3][3],
                     const jet3 jet[3])
    bool utetra_is_degenerate(const utetra *cf)
    bool utetra_is_causal(const utetra *cf)
    void utetra_reset(utetra *cf)
    void utetra_solve(utetra *cf)
    void utetra_get_lambda(utetra *cf, dbl lam[2])
    void utetra_set_lambda(utetra *cf, const dbl lam[2])
    dbl utetra_get_value(const utetra *cf)
    void utetra_get_gradient(const utetra *cf, dbl g[2])
    void utetra_get_jet(const utetra *cf, jet3 *jet)
    void utetra_get_lag_mults(const utetra *cf, dbl alpha[3])
    int utetra_get_num_iter(const utetra *cf)


cdef class Bb3Tet:
    cdef:
        dbl _c[20]

    def __cinit__(self, dbl[:] f, dbl[:, :] Df, dbl[:, :] x):
        if f.size != 4 or f.shape[0] != 4:
            raise Exception('`f` must be a length 4 vector')
        if Df.size != 12 or Df.shape[0] != 4 or Df.shape[1] != 3:
            raise Exception('`Df` must have shape (4, 3)')
        if x.size != 12 or x.shape[0] != 4 or x.shape[1] != 3:
            raise Exception('`x` must have shape (4, 3)')
        # cdef int i, j
        # cdef dbl Df_[4][3]
        # for i in range(4):
        #     for j in range(3):
        #         Df_[i][j] = Df[i, j]
        # cdef dbl x_[4][3]
        # for i in range(4):
        #     for j in range(3):
        #         x_[i][j] = x[i, j]
        bb3tet_interp3(
            &f[0],
            <const dbl (*)[3]>&Df[0, 0],
            <const dbl (*)[3]>&x[0, 0],
            self._c)

    def f(self, dbl[:] b):
        if b.size != 4 or b.shape[0] != 4:
            raise Exception('`b` must be a length 4 vector')
        return bb3tet(self._c, &b[0])

    def Df(self, dbl[:] b, dbl[:] a):
        if b.size != 4 or b.shape[0] != 4:
            raise Exception('`b` must be a length 4 vector')
        if a.size != 4 or a.shape[0] != 4:
            raise Exception('`a` must be a length 4 vector')
        return dbb3tet(self._c, &b[0], &a[0])

    def D2f(self, dbl[:] b, dbl[:, :] a):
        if b.size != 4 or b.shape[0] != 4:
            raise Exception('`b` must be a length 4 vector')
        if a.size != 12 or a.shape[0] != 3 or a.shape[4] != 4:
            raise Exception('`a` must have shape (3, 4)')
        # cdef int i, j
        # cdef dbl a_[4][3]
        # for i in range(4):
        #     for j in range(3):
        #         a_[i][j] = a[i, j]
        return d2bb3tet(self._c, &b[0], <const dbl (*)[4]>&a[0, 0])


cdef class UpdateTetra:
    cdef:
        utetra *_utetra

    def __cinit__(self, dbl[:] x, dbl[:, :] Xt, dbl[:] T, dbl[:, :] DT):
        cdef jet3 jet[3]
        cdef int i
        cdef int j
        for i in range(3):
            jet[i].f = T[i]
            jet[i].fx = DT[i, 0]
            jet[i].fy = DT[i, 1]
            jet[i].fz = DT[i, 2]
        cdef dbl Xt_[3][3]
        for i in range(3):
            for j in range(3):
                Xt_[i][j] = Xt[i, j]
        utetra_alloc(&self._utetra)
        utetra_init(self._utetra, &x[0], Xt_, jet)

    def __dealloc__(self):
        utetra_dealloc(&self._utetra)

    def is_degenerate(self):
        return utetra_is_degenerate(self._utetra)

    def reset(self):
        utetra_reset(self._utetra)

    def solve(self):
        utetra_solve(self._utetra)

    def get_lambda(self):
        cdef dbl[:] lam = np.empty((2,), dtype=np.float64)
        utetra_get_lambda(self._utetra, &lam[0])
        return np.asarray(lam)

    def set_lambda(self, dbl[:] lam):
        utetra_set_lambda(self._utetra, &lam[0])

    def get_value(self):
        return utetra_get_value(self._utetra)

    def get_gradient(self):
        cdef dbl[:] g = np.empty((2,), dtype=np.float64)
        utetra_get_gradient(self._utetra, &g[0])
        return np.asarray(g)

    def get_jet(self):
        cdef jet3 jet
        utetra_get_jet(self._utetra, &jet)
        return Jet3(jet.f, jet.fx, jet.fy, jet.fz)

    def get_lag_mults(self):
        cdef dbl[:] alpha = np.empty((3,), dtype=np.float64)
        utetra_get_lag_mults(self._utetra, &alpha[0])
        return np.asarray(alpha)

    def get_num_iter(self):
        return utetra_get_num_iter(self._utetra)

cdef class ArrayView:
    cdef:
        bool readonly
        int ndim
        void *ptr
        Py_ssize_t *shape
        Py_ssize_t *strides
        char *format
        size_t itemsize

    def __cinit__(self, int ndim):
        self.ndim = ndim
        self.shape = <Py_ssize_t *>malloc(sizeof(Py_ssize_t)*ndim)
        self.strides = <Py_ssize_t *> malloc(sizeof(Py_ssize_t)*ndim)

    def __dealloc__(self):
        free(self.shape)
        free(self.strides)

    def __getbuffer__(self, Py_buffer *buf, int flags):
        buf.buf = <char *>self.ptr
        buf.format = self.format
        buf.internal = NULL
        buf.itemsize = self.itemsize
        buf.len = self.size
        buf.ndim = self.ndim
        buf.obj = self
        buf.readonly = self.readonly
        buf.shape = self.shape
        buf.strides = self.strides
        buf.suboffsets = NULL

    def __releasebuffer__(self, Py_buffer *buf):
        pass

    @property
    def size(self):
        cdef Py_ssize_t size = 1
        for i in range(self.ndim):
            size *= self.shape[i]
        return size

cdef class _Dial3:
    cdef:
        dial3 *dial
        Py_ssize_t shape[3]
        ArrayView Toff_view
        ArrayView xsrc_view
        ArrayView state_view

    def __cinit__(self, stype stype, int[:] shape, dbl h):
        dial3_alloc(&self.dial)
        dial3_init(self.dial, stype, &shape[0], h)

        self.shape[0] = shape[0]
        self.shape[1] = shape[1]
        self.shape[2] = shape[2]

        # Strides that haven't been scaled by the size of the
        # underlying type
        cdef Py_ssize_t base_strides[3]
        base_strides[2] = 1
        base_strides[1] = self.shape[2]
        base_strides[0] = self.shape[2]*self.shape[1]

        self.Toff_view = ArrayView(3)
        self.Toff_view.readonly = False
        self.Toff_view.ptr = <void *>dial3_get_Toff_ptr(self.dial)
        self.Toff_view.shape[0] = self.shape[0]
        self.Toff_view.shape[1] = self.shape[1]
        self.Toff_view.shape[2] = self.shape[2]
        self.Toff_view.strides[0] = sizeof(dbl)*base_strides[0]
        self.Toff_view.strides[1] = sizeof(dbl)*base_strides[1]
        self.Toff_view.strides[2] = sizeof(dbl)*base_strides[2]
        self.Toff_view.format = 'd'
        self.Toff_view.itemsize = sizeof(dbl)

        self.xsrc_view = ArrayView(4)
        self.xsrc_view.readonly = False
        self.xsrc_view.ptr = <void *>dial3_get_xsrc_ptr(self.dial)
        self.xsrc_view.shape[0] = self.shape[0]
        self.xsrc_view.shape[1] = self.shape[1]
        self.xsrc_view.shape[2] = self.shape[2]
        self.xsrc_view.shape[3] = 3
        self.xsrc_view.strides[0] = 4*sizeof(dbl)*base_strides[0]
        self.xsrc_view.strides[1] = 4*sizeof(dbl)*base_strides[1]
        self.xsrc_view.strides[2] = 4*sizeof(dbl)*base_strides[2]
        self.xsrc_view.strides[3] = sizeof(dbl)
        self.xsrc_view.format = 'd'
        self.xsrc_view.itemsize = sizeof(dbl)

        self.state_view = ArrayView(3)
        self.state_view.readonly = False
        self.state_view.ptr = <void *>dial3_get_state_ptr(self.dial)
        self.state_view.shape[0] = self.shape[0]
        self.state_view.shape[1] = self.shape[1]
        self.state_view.shape[2] = self.shape[2]
        self.state_view.strides[0] = sizeof(state)*base_strides[0]
        self.state_view.strides[1] = sizeof(state)*base_strides[1]
        self.state_view.strides[2] = sizeof(state)*base_strides[2]
        self.state_view.format = 'i'
        self.state_view.itemsize = sizeof(state)

    def __dealloc__(self):
        dial3_deinit(self.dial)
        dial3_dealloc(&self.dial)

    def add_point_source(self, int[:] ind0, dbl Toff):
        dial3_add_point_source(self.dial, &ind0[0], Toff)

    def add_boundary_points(self, int[::1, :] inds):
        # TODO: handle the case where inds is in a weird format
        if inds.shape[0] != 3:
            raise Exception('inds must be an 3xN array')
        dial3_add_boundary_points(self.dial, &inds[0, 0], inds.shape[1])

    def step(self):
        dial3_step(self.dial)

    def solve(self):
        dial3_solve(self.dial)

    @property
    def Toff(self):
        return self.Toff_view

    @property
    def xsrc(self):
        return self.xsrc_view

    @property
    def state(self):
        return self.state_view

class Stype(Enum):
    Constant = 0

class State(Enum):
    Far = 0
    Trial = 1
    Valid = 2
    Boundary = 3
    AdjacentToBoundary = 4
    NewValid = 5

class Dial:

    def __init__(self, stype, shape, h):
        self.shape = shape
        self.h = h
        if len(self.shape) == 3:
            self._dial = _Dial3(stype.value, array.array('i', [*shape]), h)
        else:
            raise Exception('len(shape) == %d not supported yet' % len(shape))

    def add_point_source(self, ind0, Toff):
        self._dial.add_point_source(array.array('i', [*ind0]), Toff)

    def add_boundary_points(self, inds):
        self._dial.add_boundary_points(inds)

    def step(self):
        self._dial.step()

    def solve(self):
        self._dial.solve()

    @property
    def _x(self):
        x = np.linspace(0, self.h*self.shape[0], self.shape[0])
        return x.reshape(self.shape[0], 1, 1)

    @property
    def _y(self):
        y = np.linspace(0, self.h*self.shape[1], self.shape[1])
        return y.reshape(1, self.shape[1], 1)

    @property
    def _z(self):
        z = np.linspace(0, self.h*self.shape[2], self.shape[2])
        return z.reshape(1, 1, self.shape[2])

    @property
    def T(self):
        dx = self._x - self.xsrc[:, :, :, 0]
        dy = self._y - self.xsrc[:, :, :, 1]
        dz = self._z - self.xsrc[:, :, :, 2]
        return self.Toff + np.sqrt(dx**2 + dy**2 + dz**2)

    @property
    def Toff(self):
        return np.asarray(self._dial.Toff)

    @property
    def xsrc(self):
        return np.asarray(self._dial.xsrc)

    @property
    def state(self):
        return np.asarray(self._dial.state)

cdef class Mesh3:
    cdef:
        mesh3 *mesh

    def __cinit__(self, dbl[:, ::1] verts, size_t[:, ::1] cells):
        mesh3_alloc(&self.mesh)
        cdef size_t nverts = verts.shape[0]
        cdef size_t ncells = cells.shape[0]
        mesh3_init(self.mesh, &verts[0, 0], nverts, &cells[0, 0], ncells)

    def __dealloc__(self):
        mesh3_deinit(self.mesh)
        mesh3_dealloc(&self.mesh)

    def vc(self, size_t i):
        cdef int nvc = mesh3_nvc(self.mesh, i)
        cdef size_t[::1] vc = np.empty((nvc,), dtype=np.uintp)
        mesh3_vc(self.mesh, i, &vc[0])
        return np.asarray(vc)

    def vv(self, size_t i):
        cdef int nvv = mesh3_nvv(self.mesh, i)
        cdef size_t[::1] vv = np.empty((nvv,), dtype=np.uintp)
        mesh3_vv(self.mesh, i, &vv[0])
        return np.asarray(vv)

    def cc(self, size_t i):
        cdef int ncc = mesh3_ncc(self.mesh, i)
        cdef size_t[::1] cc = np.empty((ncc,), dtype=np.uintp)
        mesh3_cc(self.mesh, i, &cc[0])
        return np.asarray(cc)

    def cv(self, size_t i):
        cdef size_t[::1] cv = np.empty((4,), dtype=np.uintp)
        mesh3_cv(self.mesh, i, &cv[0])
        return np.asarray(cv)

    def ec(self, size_t i, size_t j):
        cdef int nec = mesh3_nec(self.mesh, i, j)
        cdef size_t[::1] ec = np.empty((nec,), dtype=np.uintp)
        mesh3_ec(self.mesh, i, j, &ec[0])
        return np.asarray(ec)

    def bdc(self, size_t i):
        return mesh3_bdc(self.mesh, i)


cdef class Jet3:
    cdef:
        jet3 jet

    def __cinit__(self, dbl f, dbl fx, dbl fy, dbl fz):
        self.jet.f = f
        self.jet.fx = fx
        self.jet.fy = fy
        self.jet.fz = fz

    @property
    def f(self):
        return self.jet.f

    @property
    def fx(self):
        return self.jet.fx

    @property
    def fy(self):
        return self.jet.fy

    @property
    def fz(self):
        return self.jet.fz


cdef class Eik3:
    cdef:
        eik3 *eik
        ArrayView jet_view
        ArrayView state_view
        ArrayView full_update_view

    def __cinit__(self, Mesh3 mesh):
        eik3_alloc(&self.eik)
        eik3_init(self.eik, mesh.mesh)

        self.jet_view = ArrayView(1)
        self.jet_view.readonly = True
        self.jet_view.ptr = <void *>eik3_get_jet_ptr(self.eik)
        self.jet_view.shape[0] = self.size
        self.jet_view.strides[0] = 4*sizeof(dbl)
        self.jet_view.format = 'dddd'
        self.jet_view.itemsize = 4*sizeof(dbl)

        self.state_view = ArrayView(1)
        self.state_view.readonly = True
        self.state_view.ptr = <void *>eik3_get_state_ptr(self.eik)
        self.state_view.shape[0] = self.size
        self.state_view.strides[0] = sizeof(state)
        self.state_view.format = 'i'
        self.state_view.itemsize = sizeof(state)

        self.full_update_view = ArrayView(1)
        self.full_update_view.readonly = True
        self.full_update_view.ptr = <void *>eik3_get_full_update_ptr(self.eik)
        self.full_update_view.shape[0] = self.size
        self.full_update_view.strides[0] = sizeof(int)
        self.full_update_view.format = 'i'
        self.full_update_view.itemsize = sizeof(int)


    def __dealloc__(self):
        eik3_deinit(self.eik)
        eik3_dealloc(&self.eik)

    def peek(self):
        return eik3_peek(self.eik)

    def step(self):
        return eik3_step(self.eik)

    def solve(self):
        eik3_solve(self.eik)

    def add_trial(self, size_t ind, Jet3 jet):
        eik3_add_trial(self.eik, ind, jet.jet)

    def add_valid(self, size_t ind, Jet3 jet):
        eik3_add_valid(self.eik, ind, jet.jet)

    def is_far(self, size_t ind):
        return eik3_is_far(self.eik, ind)

    def is_trial(self, size_t ind):
        return eik3_is_trial(self.eik, ind)

    def is_valid(self, size_t ind):
        return eik3_is_valid(self.eik, ind)

    @property
    def front(self):
        return self.peek()

    @property
    def size(self):
        cdef const mesh3 *mesh = eik3_get_mesh(self.eik)
        return mesh3_nverts(mesh)

    @property
    def jet(self):
        return np.asarray(self.jet_view)

    @property
    def state(self):
        return np.asarray(self.state_view)

    @property
    def num_full_updates(self):
        return eik3_get_num_full_updates(self.eik)

    @property
    def full_update(self):
        return np.asarray(self.full_update_view).astype(np.bool)
