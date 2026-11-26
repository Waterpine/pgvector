#ifndef VECUTILS_H
#define VECUTILS_H

#include "fmgr.h"

float		VectorL2SquaredDistance(int dim, float *ax, float *bx);
float		VectorInnerProduct(int dim, float *ax, float *bx);
double		VectorCosineSimilarity(int dim, float *ax, float *bx);
float		VectorL1Distance(int dim, float *ax, float *bx);

bool		VectorIsCosineDistance(PGFunction function);

#endif
