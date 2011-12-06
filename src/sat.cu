/**
 *  @file sat.cu
 *  @brief CUDA device code for GPU-Efficient Summed-Area Tables
 *  @author Andre Maximo
 *  @date September, 2011
 */

//== INCLUDES =================================================================

#include <dvector.h>

#include <gpufilter.h>
#include <gpudefs.cuh>
#include <gpuconsts.cuh>

#include <sat.cuh>

//== NAMESPACES ===============================================================

namespace gpufilter {

//== IMPLEMENTATION ===========================================================

//-- Algorithm SAT ------------------------------------------------------------

__global__
void algorithmSAT_stage1( const float *g_in,
                          float *g_ybar,
                          float *g_vhat ) {

	const int tx = threadIdx.x, ty = threadIdx.y, bx = blockIdx.x, by = blockIdx.y, col = bx*WS+tx, row0 = by*WS;

	__shared__ float block[ WS ][ WS+1 ];

    float (*bdata)[WS+1] = (float (*)[WS+1]) &block[ty][tx];

	g_in += (row0+ty)*c_width+col;
	g_ybar += by*c_width+col;
	g_vhat += bx*c_height+row0+tx;

#pragma unroll
    for (int i = 0; i < WS-(WS%SOW); i+=SOW) {
        **bdata = *g_in;
        bdata += SOW;
        g_in += SOW * c_width;
    }
    if( ty < WS%SOW ) {
        **bdata = *g_in;
    }

	__syncthreads();

	if( ty == 0 ) {

        {   // calculate ybar -----------------------
            float (*bdata)[WS+1] = (float (*)[WS+1]) &block[0][tx];

            float prev = **bdata;
            ++bdata;

#pragma unroll
            for (int i = 1; i < WS; ++i, ++bdata)
                **bdata = prev = **bdata + prev;

            *g_ybar = prev;
        }

        {   // calculate vhat -----------------------
            float *bdata = block[tx];

            float prev = *bdata;
            ++bdata;

#pragma unroll
            for (int i = 1; i < WS; ++i, ++bdata)
                prev = *bdata + prev;

            *g_vhat = prev;
        }

	}

}

__global__
void algorithmSAT_stage2( float *g_ybar,
                          float *g_ysum ) {

	const int tx = threadIdx.x, ty = threadIdx.y, bx = blockIdx.x, col0 = bx*MW+ty, col = col0*WS+tx;

	if( col >= c_width ) return;

	g_ybar += col;
	float y = *g_ybar;
	int ln = HWS+tx;

	if( tx == WS-1 )
		g_ysum += col0;

	volatile __shared__ float block[ MW ][ HWS+WS+1 ];

	if( tx < HWS ) block[ty][tx] = 0.f;
	else block[ty][ln] = 0.f;

	for (int m = 1; m < c_m_size; ++m) {

        // calculate ysum -----------------------

		block[ty][ln] = y;

		block[ty][ln] += block[ty][ln-1];
		block[ty][ln] += block[ty][ln-2];
		block[ty][ln] += block[ty][ln-4];
		block[ty][ln] += block[ty][ln-8];
		block[ty][ln] += block[ty][ln-16];

		if( tx == WS-1 ) {
			*g_ysum = block[ty][ln];
			g_ysum += c_n_size;
		}

        // fix ybar -> y -------------------------

		g_ybar += c_width;
		y = *g_ybar += y;

	}

}

__global__
void algorithmSAT_stage3( const float *g_ysum,
                          float *g_vhat ) {

	const int tx = threadIdx.x, ty = threadIdx.y, by = blockIdx.y, row0 = by*MW+ty, row = row0*WS+tx;

	if( row >= c_height ) return;

	g_vhat += row;
	float y = 0.f, v = 0.f;

	if( row0 > 0 )
		g_ysum += (row0-1)*c_n_size;

	for (int n = 0; n < c_n_size; ++n) {

        // fix vhat -> v -------------------------

		if( row0 > 0 ) {
			y = *g_ysum;
			g_ysum += 1;
		}

		v = *g_vhat += v + y;
		g_vhat += c_height;

	}

}

__global__
void algorithmSAT_stage4( float *g_inout,
                          const float *g_y,
                          const float *g_v ) {

	const int tx = threadIdx.x, ty = threadIdx.y, bx = blockIdx.x, by = blockIdx.y, col = bx*WS+tx, row0 = by*WS;

	__shared__ float block[ WS ][ WS+1 ];

    float (*bdata)[WS+1] = (float (*)[WS+1]) &block[ty][tx];

	g_inout += (row0+ty)*c_width+col;
	if( by > 0 ) g_y += (by-1)*c_width+col;
	if( bx > 0 ) g_v += (bx-1)*c_height+row0+tx;

#pragma unroll
    for (int i = 0; i < WS-(WS%SOW); i+=SOW) {
        **bdata = *g_inout;
        bdata += SOW;
        g_inout += SOW * c_width;
    }
    if( ty < WS%SOW ) {
        **bdata = *g_inout;
    }

	__syncthreads();

	if( ty == 0 ) {

        {   // calculate y -----------------------
            float (*bdata)[WS+1] = (float (*)[WS+1]) &block[0][tx];

            float prev;
            if( by > 0 ) prev = *g_y;
            else prev = 0.f;

#pragma unroll
            for (int i = 0; i < WS; ++i, ++bdata)
                **bdata = prev = **bdata + prev;
        }

        {   // calculate x -----------------------
            float *bdata = block[tx];

            float prev;
            if( bx > 0 ) prev = *g_v;
            else prev = 0.f;

#pragma unroll
            for (int i = 0; i < WS; ++i, ++bdata)
                *bdata = prev = *bdata + prev;
        }

	}

	__syncthreads();

    bdata = (float (*)[WS+1]) &block[ty][tx];

	g_inout -= (WS-(WS%SOW))*c_width;

#pragma unroll
    for (int i = 0; i < WS-(WS%SOW); i+=SOW) {
        *g_inout = **bdata;
        bdata += SOW;
        g_inout += SOW * c_width;
    }
    if( ty < WS%SOW ) {
        *g_inout = **bdata;
    }

}

__global__
void algorithmSAT_stage4( float *g_out,
                          const float *g_in,
                          const float *g_y,
                          const float *g_v ) {

	const int tx = threadIdx.x, ty = threadIdx.y, bx = blockIdx.x, by = blockIdx.y, col = bx*WS+tx, row0 = by*WS;

	__shared__ float block[ WS ][ WS+1 ];

    float (*bdata)[WS+1] = (float (*)[WS+1]) &block[ty][tx];

	g_in += (row0+ty)*c_width+col;
	if( by > 0 ) g_y += (by-1)*c_width+col;
	if( bx > 0 ) g_v += (bx-1)*c_height+row0+tx;

#pragma unroll
    for (int i = 0; i < WS-(WS%SOW); i+=SOW) {
        **bdata = *g_in;
        bdata += SOW;
        g_in += SOW * c_width;
    }
    if( ty < WS%SOW ) {
        **bdata = *g_in;
    }

	__syncthreads();

	if( ty == 0 ) {

        {   // calculate y -----------------------
            float (*bdata)[WS+1] = (float (*)[WS+1]) &block[0][tx];

            float prev;
            if( by > 0 ) prev = *g_y;
            else prev = 0.f;

#pragma unroll
            for (int i = 0; i < WS; ++i, ++bdata)
                **bdata = prev = **bdata + prev;
        }

        {   // calculate x -----------------------
            float *bdata = block[tx];

            float prev;
            if( bx > 0 ) prev = *g_v;
            else prev = 0.f;

#pragma unroll
            for (int i = 0; i < WS; ++i, ++bdata)
                *bdata = prev = *bdata + prev;
        }

	}

	__syncthreads();

    bdata = (float (*)[WS+1]) &block[ty][tx];

	g_out += (row0+ty)*c_width+col;

#pragma unroll
    for (int i = 0; i < WS-(WS%SOW); i+=SOW) {
        *g_out = **bdata;
        bdata += SOW;
        g_out += SOW * c_width;
    }
    if( ty < WS%SOW ) {
        *g_out = **bdata;
    }

}

//-- Host ---------------------------------------------------------------------

__host__
void prepareSAT( dvector<float>& d_in,
                 dvector<float>& d_ybar,
                 dvector<float>& d_vhat,
                 dvector<float>& d_ysum,
                 dim3& cg_img,
                 dim3& cg_ybar,
                 dim3& cg_vhat,
                 int& h_out,
                 int& w_out,
                 const float *in,
                 const int& h,
                 const int& w ) {

    h_out = h;
    w_out = w;

    if( h % 32 > 0 ) h_out += (32 - (h % 32));
    if( w % 32 > 0 ) w_out += (32 - (w % 32));

    up_constants_sizes( cg_img, h_out, w_out );

    d_in.copy_from( in, h, w, h_out, w_out );
    d_ybar.resize( cg_img.y * w_out );
    d_vhat.resize( cg_img.x * h_out );
    d_ysum.resize( cg_img.x * cg_img.y );

	const int nWm = (w_out+MTS-1)/MTS, nHm = (h_out+MTS-1)/MTS;
    cg_ybar = dim3(nWm, 1);
    cg_vhat = dim3(1, nHm);

}

__host__
void algorithmSAT( dvector<float>& d_out,
                   const dvector<float>& d_in,
                   dvector<float>& d_ybar,
                   dvector<float>& d_vhat,
                   dvector<float>& d_ysum,
                   const dim3& cg_img,
                   const dim3& cg_ybar,
                   const dim3& cg_vhat ) {

    algorithmSAT_stage1<<< cg_img, dim3(WS, SOW) >>>( d_in, d_ybar, d_vhat );

    algorithmSAT_stage2<<< cg_ybar, dim3(WS, MW) >>>( d_ybar, d_ysum );

    algorithmSAT_stage3<<< cg_vhat, dim3(WS, MW) >>>( d_ysum, d_vhat );

    algorithmSAT_stage4<<< cg_img, dim3(WS, SOW) >>>( d_out, d_in, d_ybar, d_vhat );

}

__host__
void algorithmSAT( dvector<float>& d_inout,
                   dvector<float>& d_ybar,
                   dvector<float>& d_vhat,
                   dvector<float>& d_ysum,
                   const dim3& cg_img,
                   const dim3& cg_ybar,
                   const dim3& cg_vhat ) {

    algorithmSAT_stage1<<< cg_img, dim3(WS, SOW) >>>( d_inout, d_ybar, d_vhat );

    algorithmSAT_stage2<<< cg_ybar, dim3(WS, MW) >>>( d_ybar, d_ysum );

    algorithmSAT_stage3<<< cg_vhat, dim3(WS, MW) >>>( d_ysum, d_vhat );

    algorithmSAT_stage4<<< cg_img, dim3(WS, SOW) >>>( d_inout, d_ybar, d_vhat );

}

__host__
void algorithmSAT( float *inout,
                   const int& h,
                   const int& w ) {

    dim3 cg_img, cg_ybar, cg_vhat;
    dvector<float> d_out, d_ybar, d_vhat, d_ysum;
    int h_out, w_out;

    prepareSAT( d_out, d_ybar, d_vhat, d_ysum, cg_img, cg_ybar, cg_vhat, h_out, w_out, inout, h, w );

    algorithmSAT( d_out, d_ybar, d_vhat, d_ysum, cg_img, cg_ybar, cg_vhat );

    d_out.copy_to( inout, h_out, w_out, h, w );

}

//=============================================================================
} // namespace gpufilter
//=============================================================================
