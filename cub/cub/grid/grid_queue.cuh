/******************************************************************************
 * Copyright (c) 2011, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2018, NVIDIA CORPORATION.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the NVIDIA CORPORATION nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 ******************************************************************************/

/**
 * @file
 * cub::GridQueue is a descriptor utility for dynamic queue management.
 */

#pragma once

#include <cub/config.cuh>

#if defined(_CCCL_IMPLICIT_SYSTEM_HEADER_GCC)
#  pragma GCC system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_CLANG)
#  pragma clang system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_MSVC)
#  pragma system_header
#endif // no system header

#include <cub/util_debug.cuh>

#include <nv/target>

CUB_NAMESPACE_BEGIN

/**
 * @brief GridQueue is a descriptor utility for dynamic queue management.
 *
 * @par Overview
 * GridQueue descriptors provides abstractions for "filling" or
 * "draining" globally-shared vectors.
 *
 * @par
 * A "filling" GridQueue works by atomically-adding to a zero-initialized counter,
 * returning a unique offset for the calling thread to write its items.
 * The GridQueue maintains the total "fill-size".  The fill counter must be reset
 * using GridQueue::ResetFill by the host or kernel instance prior to the kernel instance that
 * will be filling.
 *
 * @par
 * Similarly, a "draining" GridQueue works by atomically-incrementing a
 * zero-initialized counter, returning a unique offset for the calling thread to
 * read its items. Threads can safely drain until the array's logical fill-size is
 * exceeded.  The drain counter must be reset using GridQueue::ResetDrain or
 * GridQueue::FillAndResetDrain by the host or kernel instance prior to the kernel instance that
 * will be filling.  (For dynamic work distribution of existing data, the corresponding fill-size
 * is simply the number of elements in the array.)
 *
 * @par
 * Iterative work management can be implemented simply with a pair of flip-flopping
 * work buffers, each with an associated set of fill and drain GridQueue descriptors.
 *
 * @tparam OffsetT Signed integer type for global offsets
 */
template <typename OffsetT>
class GridQueue
{
private:
  /// Counter indices
  enum
  {
    FILL  = 0,
    DRAIN = 1,
  };

  /// Pair of counters
  OffsetT* d_counters;

public:
  /// Returns the device allocation size in bytes needed to construct a GridQueue instance
  _CCCL_HOST_DEVICE _CCCL_FORCEINLINE static size_t AllocationSize()
  {
    return sizeof(OffsetT) * 2;
  }

  /// Constructs an invalid GridQueue descriptor
  _CCCL_HOST_DEVICE _CCCL_FORCEINLINE GridQueue()
      : d_counters(nullptr)
  {}

  /**
   * @brief Constructs a GridQueue descriptor around the device storage allocation
   *
   * @param d_storage
   *   Device allocation to back the GridQueue.  Must be at least as big as
   *   <tt>AllocationSize()</tt>.
   */
  _CCCL_HOST_DEVICE _CCCL_FORCEINLINE GridQueue(void* d_storage)
      : d_counters((OffsetT*) d_storage)
  {}

  /// This operation sets the fill-size and resets the drain counter, preparing the GridQueue for
  /// draining in the next kernel instance. To be called by the host or by a kernel prior to the one
  /// which will be draining.
  _CCCL_HOST_DEVICE _CCCL_FORCEINLINE cudaError_t
  FillAndResetDrain(OffsetT fill_size, [[maybe_unused]] cudaStream_t stream = 0)
  {
    cudaError_t result = cudaErrorUnknown;

    NV_IF_TARGET(
      NV_IS_DEVICE,
      (d_counters[FILL] = fill_size; d_counters[DRAIN] = 0; result = cudaSuccess;),
      (OffsetT counters[2]; counters[FILL] = fill_size; counters[DRAIN] = 0;
       result = CubDebug(cudaMemcpyAsync(d_counters, counters, sizeof(OffsetT) * 2, cudaMemcpyHostToDevice, stream));));

    return result;
  }

  /// This operation resets the drain so that it may advance to meet the existing fill-size.
  /// To be called by the host or by a kernel prior to the one which will be draining.
  _CCCL_HOST_DEVICE _CCCL_FORCEINLINE cudaError_t ResetDrain([[maybe_unused]] cudaStream_t stream = 0)
  {
    cudaError_t result = cudaErrorUnknown;

    NV_IF_TARGET(NV_IS_DEVICE,
                 (d_counters[DRAIN] = 0; result = cudaSuccess;),
                 (result = CubDebug(cudaMemsetAsync(d_counters + DRAIN, 0, sizeof(OffsetT), stream));));

    return result;
  }

  /// This operation resets the fill counter.
  /// To be called by the host or by a kernel prior to the one which will be filling.
  _CCCL_HOST_DEVICE _CCCL_FORCEINLINE cudaError_t ResetFill([[maybe_unused]] cudaStream_t stream = 0)
  {
    cudaError_t result = cudaErrorUnknown;

    NV_IF_TARGET(NV_IS_DEVICE,
                 (d_counters[FILL] = 0; result = cudaSuccess;),
                 (result = CubDebug(cudaMemsetAsync(d_counters + FILL, 0, sizeof(OffsetT), stream));));

    return result;
  }

  /// Returns the fill-size established by the parent or by the previous kernel.
  _CCCL_HOST_DEVICE _CCCL_FORCEINLINE cudaError_t FillSize(OffsetT& fill_size, [[maybe_unused]] cudaStream_t stream = 0)
  {
    cudaError_t result = cudaErrorUnknown;

    NV_IF_TARGET(NV_IS_DEVICE,
                 (fill_size = d_counters[FILL]; result = cudaSuccess;),
                 (result = CubDebug(
                    cudaMemcpyAsync(&fill_size, d_counters + FILL, sizeof(OffsetT), cudaMemcpyDeviceToHost, stream));));

    return result;
  }

  /// Drain @p num_items from the queue. Returns offset from which to read items.
  /// To be called from CUDA kernel.
  _CCCL_DEVICE _CCCL_FORCEINLINE OffsetT Drain(OffsetT num_items)
  {
    return atomicAdd(d_counters + DRAIN, num_items);
  }

  /// Fill @p num_items into the queue. Returns offset from which to write items.
  /// To be called from CUDA kernel.
  _CCCL_DEVICE _CCCL_FORCEINLINE OffsetT Fill(OffsetT num_items)
  {
    return atomicAdd(d_counters + FILL, num_items);
  }
};

#ifndef _CCCL_DOXYGEN_INVOKED // Do not document

/**
 * Reset grid queue (call with 1 block of 1 thread)
 */
template <typename OffsetT>
__global__ void FillAndResetDrainKernel(GridQueue<OffsetT> grid_queue, OffsetT num_items)
{
  grid_queue.FillAndResetDrain(num_items);
}

#endif // _CCCL_DOXYGEN_INVOKED

CUB_NAMESPACE_END
