#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>
#include <algorithm>

// Single-producer / single-consumer byte ring.
class ByteRing {
public:
  explicit ByteRing(size_t capacity) : buf_(capacity), cap_(capacity) {}

  size_t size() const {
    size_t h = head_.load(std::memory_order_acquire);
    size_t t = tail_.load(std::memory_order_acquire);
    return (h >= t) ? (h - t) : (cap_ - (t - h));
  }

  bool push(const uint8_t* data, size_t len) {
    if (len == 0) return true;
    size_t h = head_.load(std::memory_order_relaxed);
    size_t t = tail_.load(std::memory_order_acquire);
    size_t used = (h >= t) ? (h - t) : (cap_ - (t - h));
    size_t free = cap_ - used - 1;
    if (len > free) return false;

    size_t chunk1 = std::min(len, cap_ - h);
    memcpy(&buf_[h], data, chunk1);
    if (len > chunk1) {
      memcpy(&buf_[0], data + chunk1, len - chunk1);
    }
    
    head_.store((h + len) % cap_, std::memory_order_release);
    return true;
  }

  // Peek without advancing tail. Returns false if not enough data.
  bool peek(uint8_t* out, size_t len) const {
    if (size() < len) return false;
    
    size_t t = tail_.load(std::memory_order_relaxed);
    size_t chunk1 = std::min(len, cap_ - t);
    memcpy(out, &buf_[t], chunk1);
    if (len > chunk1) {
      memcpy(out + chunk1, &buf_[0], len - chunk1);
    }
    return true;
  }

  // Pop n bytes. Returns actual popped.
  size_t pop(uint8_t* out, size_t maxLen) {
    size_t t = tail_.load(std::memory_order_relaxed);
    size_t avail = size(); // uses acquire load of head
    size_t n = std::min(maxLen, avail);
    if (n == 0) return 0;

    size_t chunk1 = std::min(n, cap_ - t);
    memcpy(out, &buf_[t], chunk1);
    if (n > chunk1) {
      memcpy(out + chunk1, &buf_[0], n - chunk1);
    }
    
    tail_.store((t + n) % cap_, std::memory_order_release);
    return n;
  }

  void clear() {
      head_.store(0, std::memory_order_release);
      tail_.store(0, std::memory_order_release);
  }

private:
  std::vector<uint8_t> buf_;
  const size_t cap_;
  std::atomic<size_t> head_{0};
  std::atomic<size_t> tail_{0};
};
