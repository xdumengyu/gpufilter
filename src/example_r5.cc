/**
 *  @file example_r5.cc
 *  @brief Fifth R (Recursive Filtering) example
 *  @author Andre Maximo
 *  @date February, 2012
 */

#include <ctime>
#include <cstdlib>

#include <iostream>
#include <iomanip>

#include <timer.h>
#include <cpuground.h>
#include <gpufilter.h>

#define REPEATS 100

// Check computation
void check_reference( const float *ref,
                      const float *res,
                      const int& ne,
                      float& me,
                      float& mre ) {
    mre = me = (float)0;
    for (int i = 0; i < ne; i++) {
        float a = (float)(res[i]) - ref[i];
        if( a < (float)0 ) a = -a;
        if( ref[i] != (float)0 ) {
            float r = (ref[i] < (float)0) ? -ref[i] : ref[i];
            float b = a / r;
            mre = b > mre ? b : mre;
        }
        me = a > me ? a : me;
    }
}

// Main
int main(int argc, char *argv[]) {

    const int in_w = 4096, in_h = 4096;
    const float b0 = 0.992817, a1 = -0.00719617, a2 = 1.29475e-05;

    std::cout << "[r5] Generating random input image (" << in_w << "x" << in_h << ") ... " << std::flush;

    float *in_cpu = new float[in_h*in_w];
    float *in_gpu = new float[in_h*in_w];

    srand(time(0));

    for (int i = 0; i < in_h*in_w; ++i)
        in_gpu[i] = in_cpu[i] = rand() / (float)RAND_MAX;

    std::cout << "done!\n[r5] Recursive filter: y_i = b0 * x_i - a1 * y_{i-1} - a2 * y_{i-2}\n";
    std::cout << "[r5] Considering forward and reverse on rows and columns\n";
    std::cout << "[r5] Coefficients are: b0 = " << b0 << " ; a1 = " << a1 << " ; a2 = " << a2 << "\n";
    std::cout << "[r5] CPU Computing second-order recursive filtering ... " << std::flush;

    std::cout << std::fixed << std::setprecision(2);

    {
        gpufilter::scoped_timer_stop sts( gpufilter::timers.cpu_add("CPU", in_h*in_w, "iP") );

        gpufilter::r( in_cpu, in_h, in_w, b0, a1, a2 );
    }

    std::cout << "done!\n[r5] Configuring the GPU to run ... " << std::flush;

    dim3 cg_img;
    gpufilter::dvector<float> d_out, d_transp_out;
    gpufilter::dvector<float2> d_transp_pybar, d_transp_ezhat, d_pubar, d_evhat;
    int transp_out_height;
    cudaArray *a_in;

    gpufilter::prepare_alg4( d_out, d_transp_out, transp_out_height, a_in,
                             d_transp_pybar, d_transp_ezhat, d_pubar, d_evhat,
                             cg_img, in_gpu, in_h, in_w, b0, a1, a2 );

    std::cout << "done!\n[r5] GPU Computing second-order recursive filtering using Algorithm 4 ... " << std::flush;

    {
        gpufilter::scoped_timer_stop sts( gpufilter::timers.gpu_add("GPU", in_h*in_w*REPEATS, "iP") );

        for (int i = 0; i < REPEATS; ++i)
            gpufilter::alg4( d_out, d_transp_out, transp_out_height, in_h, in_w, a_in,
                             d_transp_pybar, d_transp_ezhat, d_pubar, d_evhat, cg_img );
    }

    std::cout << "done!\n";

    gpufilter::timers.flush();

    std::cout << "[r5] Copying result back from the GPU ... " << std::flush;

    d_out.copy_to( in_gpu, in_h * in_w );

    cudaFreeArray( a_in );

    std::cout << "done!\n[r5] Checking GPU result with CPU reference values\n";

    float me, mre;

    check_reference( in_cpu, in_gpu, in_h*in_w, me, mre );

    std::cout << std::scientific;

    std::cout << "[r5] Maximum relative error: " << mre << " ; Maximum error: " << me << "\n";

    delete [] in_cpu;
    delete [] in_gpu;

    return 0;

}
