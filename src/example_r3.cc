/**
 *  @file example_r3.cc
 *  @brief Third R (Recursive Filtering) example
 *  @author Andre Maximo
 *  @date November, 2011
 */

#include <ctime>
#include <cstdlib>

#include <iostream>
#include <iomanip>

#include <timer.h>
#include <cpuground.h>
#include <gpufilter.h>

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

    const int w_in = 1024, h_in = 1024;
    const float b0 = .0417f, a1 = -1.704f, a2 = .746f;

    std::cout << "[r3] Generating random input image (" << w_in << "x" << h_in << ") ... " << std::flush;

    float *in_cpu = new float[h_in*w_in];
    float *in_gpu = new float[h_in*w_in];

    srand(time(0));

    for (int i = 0; i < h_in*w_in; ++i)
        in_gpu[i] = in_cpu[i] = rand() / (float)RAND_MAX;

    std::cout << "done!\n[r3] Recursive filter: y_i = b0 * x_i - a1 * y_{i-1} - a2 * y_{i-2}\n";
    std::cout << "[r3] Considering forward and reverse on rows and columns\n";
    std::cout << "[r3] Coefficients are: b0 = " << b0 << " ; a1 = " << a1 << " ; a2 = " << a2 << "\n";
    std::cout << "[r3] CPU Computing second-order recursive filtering with zero-border ... " << std::flush;

    std::cout << std::fixed << std::setprecision(2);

    {
        gpufilter::scoped_timer_stop sts( gpufilter::timers.cpu_add("CPU") );

        gpufilter::r( in_cpu, h_in, w_in, b0, a1, a2 );

        std::cout << "done!\n[r3] CPU Timing: " << sts.elapsed()*1000 << " ms\n";
    }

    std::cout << "[r3] GPU Computing second-order recursive filtering with zero-border ... " << std::flush;

    {
        gpufilter::scoped_timer_stop sts( gpufilter::timers.gpu_add("GPU") );

        gpufilter::algorithm4( in_gpu, h_in, w_in, b0, a1, a2 );

        std::cout << "done!\n[r3] GPU Timing: " << sts.elapsed()*1000 << " ms\n";
    }

    std::cout << "[r3] GPU Timing includes pre-computation and memory transfers\n";

    std::cout << "[r3] Checking GPU result with CPU reference values\n";

    float me, mre;

    check_reference( in_cpu, in_gpu, h_in*w_in, me, mre );

    std::cout << std::scientific;

    std::cout << "[r3] Maximum error: " << me << "\n";

    delete [] in_cpu;
    delete [] in_gpu;

    return 0;

}
