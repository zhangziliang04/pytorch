#ifndef THC_GENERIC_FILE
#define THC_GENERIC_FILE "generic/BatchNormalization.cu"
#else

#define DeviceTensor3 THCDeviceTensor<real, 3>
#define DeviceTensor1 THCDeviceTensor<real, 1>

template <int Dim>
static THCDeviceTensor<real, Dim> THNN_(devicetensor)(THCState *state, THCTensor *t) {
  if (!t) {
    return THCDeviceTensor<real, Dim>();
  }

  int inDim = THCTensor_nDimensionLegacyAll(state, t);
  if (inDim == Dim) {
    return toDeviceTensor<real, Dim>(state, t);
  }

  // View in which the last dimensions are collapsed or expanded as needed
  THAssert(THCTensor_isContiguous(state, t));
  int size[Dim];
  for (int i = 0; i < Dim || i < inDim; ++i) {
    if (i < Dim && i < inDim) {
      size[i] = THTensor_sizeLegacyNoScalars(t, i);
    } else if (i < Dim) {
      size[i] = 1;
    } else {
      size[Dim - 1] *= THTensor_sizeLegacyNoScalars(t, i);
    }
  }
  return THCDeviceTensor<real, Dim>(t->data<real>(), size);
}

void THNN_(BatchNormalization_updateOutput)(
  THCState *state, THCTensor *input_, THCTensor *output_,
  THCTensor *weight_, THCTensor *bias_, THCTensor *runningMean_,
  THCTensor *runningVar_, THCTensor *saveMean_, THCTensor *saveStd_,
  bool train, double momentum, double eps) {

  THCTensor_(resizeAs)(state, output_, input_);
  if (train) {
    int64_t nInput = THCTensor_(size)(state, input_, 1);
    THCTensor_(resize1d)(state, saveMean_, nInput);
    THCTensor_(resize1d)(state, saveStd_, nInput);
  }
  DeviceTensor3 input = THNN_(devicetensor)<3>(state, input_);
  DeviceTensor3 output = THNN_(devicetensor)<3>(state, output_);
  DeviceTensor1 weight = THNN_(devicetensor)<1>(state, weight_);
  DeviceTensor1 bias = THNN_(devicetensor)<1>(state, bias_);
  DeviceTensor1 runningMean = THNN_(devicetensor)<1>(state, runningMean_);
  DeviceTensor1 runningVar = THNN_(devicetensor)<1>(state, runningVar_);
  DeviceTensor1 saveMean = THNN_(devicetensor)<1>(state, saveMean_);
  DeviceTensor1 saveStd = THNN_(devicetensor)<1>(state, saveStd_);

  cudaStream_t s = THCState_getCurrentStream(state);
  cudaDeviceProp *prop = THCState_getCurrentDeviceProperties(state);

  if (!train) {
    dim3 blocks(input.getSize(1));
    dim3 threads(getNumThreads(input.getSize(2)));
    BatchNormalizationUpdateOutputInference_kernel<real, accreal, DeviceTensor1, DeviceTensor3> <<<blocks, threads, 0, s>>>(
      input, output, runningMean, runningVar, weight, bias, eps);
  } else {
    dim3 blocks(input.getSize(1));
    dim3 threads(getNumThreads(input.getSize(2)));
    BatchNormalizationUpdateOutput_kernel<real, accreal, DeviceTensor1, DeviceTensor3> <<<blocks, threads, 0, s>>>(
      input, output, weight, bias, eps, momentum, runningMean, runningVar,
      saveMean, saveStd);
  }
  THCudaCheck(cudaGetLastError());
}

void THNN_(BatchNormalization_backward)(
  THCState *state, THCTensor *input_, THCTensor *gradOutput_,
  THCTensor *gradInput_, THCTensor *gradWeight_, THCTensor *gradBias_,
  THCTensor *weight_, THCTensor *runningMean_, THCTensor *runningVar_,
  THCTensor *saveMean_, THCTensor *saveStd_, bool train, double scale, double eps) {

  THCUNN_check_shape(state, input_, gradOutput_);
  if (gradInput_) {
    THCTensor_(resizeAs)(state, gradInput_, input_);
  }

  DeviceTensor3 input = THNN_(devicetensor)<3>(state, input_);
  DeviceTensor3 gradOutput = THNN_(devicetensor)<3>(state, gradOutput_);
  DeviceTensor3 gradInput = THNN_(devicetensor)<3>(state, gradInput_);
  DeviceTensor1 gradWeight = THNN_(devicetensor)<1>(state, gradWeight_);
  DeviceTensor1 gradBias = THNN_(devicetensor)<1>(state, gradBias_);
  DeviceTensor1 weight = THNN_(devicetensor)<1>(state, weight_);
  DeviceTensor1 runningMean = THNN_(devicetensor)<1>(state, runningMean_);
  DeviceTensor1 runningVar = THNN_(devicetensor)<1>(state, runningVar_);
  DeviceTensor1 saveMean = THNN_(devicetensor)<1>(state, saveMean_);
  DeviceTensor1 saveStd = THNN_(devicetensor)<1>(state, saveStd_);

  cudaStream_t s = THCState_getCurrentStream(state);

  dim3 blocks(gradOutput.getSize(1));
  dim3 threads(getNumThreads(gradOutput.getSize(2)));
  BatchNormalizationBackward_kernel<real,  accreal,  DeviceTensor1, DeviceTensor3> <<<blocks, threads, 0, s>>>(
    input, gradOutput, gradInput, gradWeight, gradBias, weight, runningMean, runningVar,
    saveMean, saveStd, train, scale, eps);
  THCudaCheck(cudaGetLastError());
}

#undef DeviceTensor3
#undef DeviceTensor1

#endif
