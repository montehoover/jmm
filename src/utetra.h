#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include "jet.h"

typedef struct eik3 eik3_s;
typedef struct mesh3 mesh3_s;

typedef struct utetra utetra_s;

void utetra_alloc(utetra_s **cf);
void utetra_dealloc(utetra_s **cf);
void utetra_reset(utetra_s *cf);
bool utetra_init_from_eik3(utetra_s *cf, eik3_s const *eik,
                           size_t l, size_t l0, size_t l1, size_t l2);
bool utetra_init_from_ptrs(utetra_s *cf, mesh3_s const *mesh, jet3 const *jet,
                           size_t l, size_t l0, size_t l1, size_t l2);
bool utetra_init(utetra_s *cf, dbl const x[3], dbl const Xt[3][3],
                 jet3 const jet[3]);
bool utetra_is_degenerate(utetra_s const *cf);
bool utetra_is_causal(utetra_s const *cf);
void utetra_solve(utetra_s *cf);
void utetra_get_lambda(utetra_s const *cf, dbl lam[2]);
void utetra_set_lambda(utetra_s *cf, dbl const lam[2]);
void utetra_get_bary_coords(utetra_s const *cf, dbl b[3]);
dbl utetra_get_value(utetra_s const *cf);
void utetra_get_gradient(utetra_s const *cf, dbl g[2]);
void utetra_get_jet(utetra_s const *cf, jet3 *jet);
void utetra_get_lag_mults(utetra_s const *cf, dbl alpha[3]);
int utetra_get_num_iter(utetra_s const *cf);
bool utetra_has_interior_point_solution(utetra_s const *cf);
int utetra_cmp(utetra_s const **h1, utetra_s const **h2);
bool utetra_adj_are_optimal(utetra_s const *u1, utetra_s const *u2);
bool utetra_diff(utetra_s const *utetra, mesh3_s const *mesh, size_t const l[3]);
void utetra_get_point_on_ray(utetra_s const *utri, dbl t, dbl xt[3]);
bool utetra_update_ray_is_physical(utetra_s const *utetra, eik3_s const *eik);
int utetra_get_num_interior_coefs(utetra_s const *utetra);
void utetra_get_update_inds(utetra_s const *utetra, size_t l[3]);
bool utetra_has_shadow_solution(utetra_s const *utetra, eik3_s const *eik);

bool utetras_yield_same_update(utetra_s const **utetra, int n);

#ifdef __cplusplus
}
#endif