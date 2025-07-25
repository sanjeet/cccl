//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

// <cuda/std/tuple>

// template <class... Types> class tuple;

// template <size_t I, class... Types>
//   typename tuple_element<I, tuple<Types...> >::type&&
//   get(tuple<Types...>&& t);

#include <cuda/std/__memory_>
#include <cuda/std/cassert>
#include <cuda/std/tuple>
#include <cuda/std/utility>

#include "MoveOnly.h"
#include "test_macros.h"

int main(int, char**)
{
  {
    using T = cuda::std::tuple<cuda::std::unique_ptr<int>>;
    T t(cuda::std::unique_ptr<int>(new int(3)));
    cuda::std::unique_ptr<int> p = cuda::std::get<0>(cuda::std::move(t));
    assert(*p == 3);
  }

  {
    cuda::std::tuple<MoveOnly> t(3);
    MoveOnly _m = cuda::std::get<0>(cuda::std::move(t));
    assert(_m.get() == 3);
  }
  return 0;
}
