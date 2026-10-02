/* Stable tooling trace ABI. Raw binary64 checkpoints, not a public math API. */
#ifndef JONLIB_MODERN_ATAN2F_TRACE_H
#define JONLIB_MODERN_ATAN2F_TRACE_H
#include <stdint.h>
#define MA_TRACE_CAPACITY 128
struct ma_event { unsigned tag; uint64_t bits; };
struct ma_trace_state {
  unsigned mask, count, overflow, gt, index, enabled;
  uint64_t final;
  struct ma_event events[MA_TRACE_CAPACITY];
};
extern struct ma_trace_state ma_trace;
static inline void ma_record(unsigned tag, double value) {
  if (!ma_trace.enabled) return;
  if (ma_trace.count >= MA_TRACE_CAPACITY) { ma_trace.overflow=1; return; }
  struct ma_event *p=&ma_trace.events[ma_trace.count++];
  p->tag=tag; p->bits=asuint64(value);
}
static inline double ma_return64(double value) {
  ma_trace.final=asuint64(value); return value;
}
#define MA_RETURN(value) ma_return64(value)
#define MA_TRACE(tag,value) ma_record((tag),(value))
#define MA_FLAG(mask_value) (ma_trace.mask |= (mask_value))
#endif
