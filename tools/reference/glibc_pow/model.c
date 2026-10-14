/* Explicit-operation model of glibc 2.39's x86_64 pow (x, y): Arm
   optimized-routines' math/pow.c with pow_log_data.c and exp_data.c
   (Copyright (c) 2018-2026 Arm Limited, MIT alternative, see
   LICENSES/arm-math.txt), as glibc builds it (POW_LOG_TABLE_BITS 7,
   EXP_TABLE_BITS 7, TOINT_INTRINSICS 0, WANT_ROUNDING 1). FUSED=1 is the
   __pow_fma ifunc variant (-mfma -mavx2), read from the host library's code:
   beside the source's own fma calls (z*invc - 1, ar*r - ar2 and y*hi - ehi),
   kd*Ln2hi + logc, kd*Ln2lo + logctail, each a + r*b of the two polynomials,
   their sums with ar2 and r2 products, ar3*(...) + (lo1 + lo2 + lo3 + lo4),
   y*lo + (...), InvLn2N*x + Shift, kd*NegLn2hiN + x, kd*NegLn2loN + (...) and
   scale*tmp + scale are one fma each. FUSED=0 is the SSE2 default: the
   source's branch without fma, every operation rounded by itself.
   The tables and the polynomials are the words of pow_log_data.c and
   exp_data.c, which are the words of the host's libm.so.6.

   The domain: the rounding mode is to nearest and no flag or errno is
   modelled. *refused is set, and 0 returned, where the model does not follow
   the library: a result that overflows or underflows or is near either
   (|y*log(x)| >= 512: the library's specialcase), and a signaling NaN.
   Compile with -ffp-contract=off. */
#include <math.h>
#include <stdint.h>
#include <string.h>
#if FUSED
#define MADD(a, b, c) fma ((a), (b), (c))
#else
#define MADD(a, b, c) ((a) * (b) + (c))
#endif
static const uint64_t LN2[2] = {0x3fe62e42fefa3800ULL, 0x3d2ef35793c76730ULL};
/* poly: A[0] is -0.5. */
static const uint64_t A[7] = {
  0xbfe0000000000000ULL, 0xbfe5555555555560ULL, 0x3fe0000000000006ULL, 0x3fe999999959554eULL,
  0xbfe555555529a47aULL, 0xbff2495b9b4845e9ULL, 0x3ff0002b8b263fc3ULL};
/* invc, logc and logctail of the 128 intervals. */
static const uint64_t L[384] = {
  0x3ff6a00000000000ULL, 0xbfd62c82f2b9c800ULL, 0x3cfab42428375680ULL,
  0x3ff6800000000000ULL, 0xbfd5d1bdbf580800ULL, 0xbd1ca508d8e0f720ULL,
  0x3ff6600000000000ULL, 0xbfd5767717455800ULL, 0xbd2362a4d5b6506dULL,
  0x3ff6400000000000ULL, 0xbfd51aad872df800ULL, 0xbce684e49eb067d5ULL,
  0x3ff6200000000000ULL, 0xbfd4be5f95777800ULL, 0xbd041b6993293ee0ULL,
  0x3ff6000000000000ULL, 0xbfd4618bc21c6000ULL, 0x3d13d82f484c84ccULL,
  0x3ff5e00000000000ULL, 0xbfd404308686a800ULL, 0x3cdc42f3ed820b3aULL,
  0x3ff5c00000000000ULL, 0xbfd3a64c55694800ULL, 0x3d20b1c686519460ULL,
  0x3ff5a00000000000ULL, 0xbfd347dd9a988000ULL, 0x3d25594dd4c58092ULL,
  0x3ff5800000000000ULL, 0xbfd2e8e2bae12000ULL, 0x3d267b1e99b72bd8ULL,
  0x3ff5600000000000ULL, 0xbfd2895a13de8800ULL, 0x3d15ca14b6cfb03fULL,
  0x3ff5600000000000ULL, 0xbfd2895a13de8800ULL, 0x3d15ca14b6cfb03fULL,
  0x3ff5400000000000ULL, 0xbfd22941fbcf7800ULL, 0xbd165a242853da76ULL,
  0x3ff5200000000000ULL, 0xbfd1c898c1699800ULL, 0xbd1fafbc68e75404ULL,
  0x3ff5000000000000ULL, 0xbfd1675cababa800ULL, 0x3d1f1fc63382a8f0ULL,
  0x3ff4e00000000000ULL, 0xbfd1058bf9ae4800ULL, 0xbd26a8c4fd055a66ULL,
  0x3ff4c00000000000ULL, 0xbfd0a324e2739000ULL, 0xbd0c6bee7ef4030eULL,
  0x3ff4a00000000000ULL, 0xbfd0402594b4d000ULL, 0xbcf036b89ef42d7fULL,
  0x3ff4a00000000000ULL, 0xbfd0402594b4d000ULL, 0xbcf036b89ef42d7fULL,
  0x3ff4800000000000ULL, 0xbfcfb9186d5e4000ULL, 0x3d0d572aab993c87ULL,
  0x3ff4600000000000ULL, 0xbfcef0adcbdc6000ULL, 0x3d2b26b79c86af24ULL,
  0x3ff4400000000000ULL, 0xbfce27076e2af000ULL, 0xbd172f4f543fff10ULL,
  0x3ff4200000000000ULL, 0xbfcd5c216b4fc000ULL, 0x3d21ba91bbca681bULL,
  0x3ff4000000000000ULL, 0xbfcc8ff7c79aa000ULL, 0x3d27794f689f8434ULL,
  0x3ff4000000000000ULL, 0xbfcc8ff7c79aa000ULL, 0x3d27794f689f8434ULL,
  0x3ff3e00000000000ULL, 0xbfcbc286742d9000ULL, 0x3d194eb0318bb78fULL,
  0x3ff3c00000000000ULL, 0xbfcaf3c94e80c000ULL, 0x3cba4e633fcd9066ULL,
  0x3ff3a00000000000ULL, 0xbfca23bc1fe2b000ULL, 0xbd258c64dc46c1eaULL,
  0x3ff3a00000000000ULL, 0xbfca23bc1fe2b000ULL, 0xbd258c64dc46c1eaULL,
  0x3ff3800000000000ULL, 0xbfc9525a9cf45000ULL, 0xbd2ad1d904c1d4e3ULL,
  0x3ff3600000000000ULL, 0xbfc87fa06520d000ULL, 0x3d2bbdbf7fdbfa09ULL,
  0x3ff3400000000000ULL, 0xbfc7ab890210e000ULL, 0x3d2bdb9072534a58ULL,
  0x3ff3400000000000ULL, 0xbfc7ab890210e000ULL, 0x3d2bdb9072534a58ULL,
  0x3ff3200000000000ULL, 0xbfc6d60fe719d000ULL, 0xbd10e46aa3b2e266ULL,
  0x3ff3000000000000ULL, 0xbfc5ff3070a79000ULL, 0xbd1e9e439f105039ULL,
  0x3ff3000000000000ULL, 0xbfc5ff3070a79000ULL, 0xbd1e9e439f105039ULL,
  0x3ff2e00000000000ULL, 0xbfc526e5e3a1b000ULL, 0xbd20de8b90075b8fULL,
  0x3ff2c00000000000ULL, 0xbfc44d2b6ccb8000ULL, 0x3d170cc16135783cULL,
  0x3ff2c00000000000ULL, 0xbfc44d2b6ccb8000ULL, 0x3d170cc16135783cULL,
  0x3ff2a00000000000ULL, 0xbfc371fc201e9000ULL, 0x3cf178864d27543aULL,
  0x3ff2800000000000ULL, 0xbfc29552f81ff000ULL, 0xbd248d301771c408ULL,
  0x3ff2600000000000ULL, 0xbfc1b72ad52f6000ULL, 0xbd2e80a41811a396ULL,
  0x3ff2600000000000ULL, 0xbfc1b72ad52f6000ULL, 0xbd2e80a41811a396ULL,
  0x3ff2400000000000ULL, 0xbfc0d77e7cd09000ULL, 0x3d0a699688e85bf4ULL,
  0x3ff2400000000000ULL, 0xbfc0d77e7cd09000ULL, 0x3d0a699688e85bf4ULL,
  0x3ff2200000000000ULL, 0xbfbfec9131dbe000ULL, 0xbd2575545ca333f2ULL,
  0x3ff2000000000000ULL, 0xbfbe27076e2b0000ULL, 0x3d2a342c2af0003cULL,
  0x3ff2000000000000ULL, 0xbfbe27076e2b0000ULL, 0x3d2a342c2af0003cULL,
  0x3ff1e00000000000ULL, 0xbfbc5e548f5bc000ULL, 0xbd1d0c57585fbe06ULL,
  0x3ff1c00000000000ULL, 0xbfba926d3a4ae000ULL, 0x3d253935e85baac8ULL,
  0x3ff1c00000000000ULL, 0xbfba926d3a4ae000ULL, 0x3d253935e85baac8ULL,
  0x3ff1a00000000000ULL, 0xbfb8c345d631a000ULL, 0x3d137c294d2f5668ULL,
  0x3ff1a00000000000ULL, 0xbfb8c345d631a000ULL, 0x3d137c294d2f5668ULL,
  0x3ff1800000000000ULL, 0xbfb6f0d28ae56000ULL, 0xbd269737c93373daULL,
  0x3ff1600000000000ULL, 0xbfb51b073f062000ULL, 0x3d1f025b61c65e57ULL,
  0x3ff1600000000000ULL, 0xbfb51b073f062000ULL, 0x3d1f025b61c65e57ULL,
  0x3ff1400000000000ULL, 0xbfb341d7961be000ULL, 0x3d2c5edaccf913dfULL,
  0x3ff1400000000000ULL, 0xbfb341d7961be000ULL, 0x3d2c5edaccf913dfULL,
  0x3ff1200000000000ULL, 0xbfb16536eea38000ULL, 0x3d147c5e768fa309ULL,
  0x3ff1000000000000ULL, 0xbfaf0a30c0118000ULL, 0x3d2d599e83368e91ULL,
  0x3ff1000000000000ULL, 0xbfaf0a30c0118000ULL, 0x3d2d599e83368e91ULL,
  0x3ff0e00000000000ULL, 0xbfab42dd71198000ULL, 0x3d1c827ae5d6704cULL,
  0x3ff0e00000000000ULL, 0xbfab42dd71198000ULL, 0x3d1c827ae5d6704cULL,
  0x3ff0c00000000000ULL, 0xbfa77458f632c000ULL, 0xbd2cfc4634f2a1eeULL,
  0x3ff0c00000000000ULL, 0xbfa77458f632c000ULL, 0xbd2cfc4634f2a1eeULL,
  0x3ff0a00000000000ULL, 0xbfa39e87b9fec000ULL, 0x3cf502b7f526feaaULL,
  0x3ff0a00000000000ULL, 0xbfa39e87b9fec000ULL, 0x3cf502b7f526feaaULL,
  0x3ff0800000000000ULL, 0xbf9f829b0e780000ULL, 0xbd2980267c7e09e4ULL,
  0x3ff0800000000000ULL, 0xbf9f829b0e780000ULL, 0xbd2980267c7e09e4ULL,
  0x3ff0600000000000ULL, 0xbf97b91b07d58000ULL, 0xbd288d5493faa639ULL,
  0x3ff0400000000000ULL, 0xbf8fc0a8b0fc0000ULL, 0xbcdf1e7cf6d3a69cULL,
  0x3ff0400000000000ULL, 0xbf8fc0a8b0fc0000ULL, 0xbcdf1e7cf6d3a69cULL,
  0x3ff0200000000000ULL, 0xbf7fe02a6b100000ULL, 0xbd19e23f0dda40e4ULL,
  0x3ff0200000000000ULL, 0xbf7fe02a6b100000ULL, 0xbd19e23f0dda40e4ULL,
  0x3ff0000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL,
  0x3ff0000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL,
  0x3fefc00000000000ULL, 0x3f80101575890000ULL, 0xbd10c76b999d2be8ULL,
  0x3fef800000000000ULL, 0x3f90205658938000ULL, 0xbd23dc5b06e2f7d2ULL,
  0x3fef400000000000ULL, 0x3f98492528c90000ULL, 0xbd2aa0ba325a0c34ULL,
  0x3fef000000000000ULL, 0x3fa0415d89e74000ULL, 0x3d0111c05cf1d753ULL,
  0x3feec00000000000ULL, 0x3fa466aed42e0000ULL, 0xbd2c167375bdfd28ULL,
  0x3fee800000000000ULL, 0x3fa894aa149fc000ULL, 0xbd197995d05a267dULL,
  0x3fee400000000000ULL, 0x3faccb73cdddc000ULL, 0xbd1a68f247d82807ULL,
  0x3fee200000000000ULL, 0x3faeea31c006c000ULL, 0xbd0e113e4fc93b7bULL,
  0x3fede00000000000ULL, 0x3fb1973bd1466000ULL, 0xbd25325d560d9e9bULL,
  0x3feda00000000000ULL, 0x3fb3bdf5a7d1e000ULL, 0x3d2cc85ea5db4ed7ULL,
  0x3fed600000000000ULL, 0x3fb5e95a4d97a000ULL, 0xbd2c69063c5d1d1eULL,
  0x3fed400000000000ULL, 0x3fb700d30aeac000ULL, 0x3cec1e8da99ded32ULL,
  0x3fed000000000000ULL, 0x3fb9335e5d594000ULL, 0x3d23115c3abd47daULL,
  0x3fecc00000000000ULL, 0x3fbb6ac88dad6000ULL, 0xbd1390802bf768e5ULL,
  0x3feca00000000000ULL, 0x3fbc885801bc4000ULL, 0x3d2646d1c65aacd3ULL,
  0x3fec600000000000ULL, 0x3fbec739830a2000ULL, 0xbd2dc068afe645e0ULL,
  0x3fec400000000000ULL, 0x3fbfe89139dbe000ULL, 0xbd2534d64fa10afdULL,
  0x3fec000000000000ULL, 0x3fc1178e8227e000ULL, 0x3d21ef78ce2d07f2ULL,
  0x3febe00000000000ULL, 0x3fc1aa2b7e23f000ULL, 0x3d2ca78e44389934ULL,
  0x3feba00000000000ULL, 0x3fc2d1610c868000ULL, 0x3d039d6ccb81b4a1ULL,
  0x3feb800000000000ULL, 0x3fc365fcb0159000ULL, 0x3cc62fa8234b7289ULL,
  0x3feb400000000000ULL, 0x3fc4913d8333b000ULL, 0x3d25837954fdb678ULL,
  0x3feb200000000000ULL, 0x3fc527e5e4a1b000ULL, 0x3d2633e8e5697dc7ULL,
  0x3feae00000000000ULL, 0x3fc6574ebe8c1000ULL, 0x3d19cf8b2c3c2e78ULL,
  0x3feac00000000000ULL, 0x3fc6f0128b757000ULL, 0xbd25118de59c21e1ULL,
  0x3feaa00000000000ULL, 0x3fc7898d85445000ULL, 0xbd1c661070914305ULL,
  0x3fea600000000000ULL, 0x3fc8beafeb390000ULL, 0xbd073d54aae92cd1ULL,
  0x3fea400000000000ULL, 0x3fc95a5adcf70000ULL, 0x3d07f22858a0ff6fULL,
  0x3fea000000000000ULL, 0x3fca93ed3c8ae000ULL, 0xbd28724350562169ULL,
  0x3fe9e00000000000ULL, 0x3fcb31d8575bd000ULL, 0xbd0c358d4eace1aaULL,
  0x3fe9c00000000000ULL, 0x3fcbd087383be000ULL, 0xbd2d4bc4595412b6ULL,
  0x3fe9a00000000000ULL, 0x3fcc6ffbc6f01000ULL, 0xbcf1ec72c5962bd2ULL,
  0x3fe9600000000000ULL, 0x3fcdb13db0d49000ULL, 0xbd2aff2af715b035ULL,
  0x3fe9400000000000ULL, 0x3fce530effe71000ULL, 0x3cc212276041f430ULL,
  0x3fe9200000000000ULL, 0x3fcef5ade4dd0000ULL, 0xbcca211565bb8e11ULL,
  0x3fe9000000000000ULL, 0x3fcf991c6cb3b000ULL, 0x3d1bcbecca0cdf30ULL,
  0x3fe8c00000000000ULL, 0x3fd07138604d5800ULL, 0x3cf89cdb16ed4e91ULL,
  0x3fe8a00000000000ULL, 0x3fd0c42d67616000ULL, 0x3d27188b163ceae9ULL,
  0x3fe8800000000000ULL, 0x3fd1178e8227e800ULL, 0xbd2c210e63a5f01cULL,
  0x3fe8600000000000ULL, 0x3fd16b5ccbacf800ULL, 0x3d2b9acdf7a51681ULL,
  0x3fe8400000000000ULL, 0x3fd1bf99635a6800ULL, 0x3d2ca6ed5147bdb7ULL,
  0x3fe8200000000000ULL, 0x3fd214456d0eb800ULL, 0x3d0a87deba46baeaULL,
  0x3fe7e00000000000ULL, 0x3fd2bef07cdc9000ULL, 0x3d2a9cfa4a5004f4ULL,
  0x3fe7c00000000000ULL, 0x3fd314f1e1d36000ULL, 0xbd28e27ad3213cb8ULL,
  0x3fe7a00000000000ULL, 0x3fd36b6776be1000ULL, 0x3d116ecdb0f177c8ULL,
  0x3fe7800000000000ULL, 0x3fd3c25277333000ULL, 0x3d183b54b606bd5cULL,
  0x3fe7600000000000ULL, 0x3fd419b423d5e800ULL, 0x3d08e436ec90e09dULL,
  0x3fe7400000000000ULL, 0x3fd4718dc271c800ULL, 0xbd2f27ce0967d675ULL,
  0x3fe7200000000000ULL, 0x3fd4c9e09e173000ULL, 0xbd2e20891b0ad8a4ULL,
  0x3fe7000000000000ULL, 0x3fd522ae0738a000ULL, 0x3d2ebe708164c759ULL,
  0x3fe6e00000000000ULL, 0x3fd57bf753c8d000ULL, 0x3d1fadedee5d40efULL,
  0x3fe6c00000000000ULL, 0x3fd5d5bddf596000ULL, 0xbd0a0b2a08a465dcULL};
/* invln2N, shift, negln2hiN, negln2loN. */
static const uint64_t E[4] = {
  0x40671547652b82feULL, 0x4338000000000000ULL, 0xbf762e42fefa0000ULL, 0xbd0cf79abc9e3b3aULL};
/* C2 to C5. */
static const uint64_t C[4] = {
  0x3fdffffffffffdbdULL, 0x3fc555555555543cULL, 0x3fa55555cf172b91ULL, 0x3f81111167a4d017ULL};
/* tail and scale bits of 2^(k/128). */
static const uint64_t T[256] = {
  0x0000000000000000ULL, 0x3ff0000000000000ULL, 0x3c9b3b4f1a88bf6eULL, 0x3feff63da9fb3335ULL,
  0xbc7160139cd8dc5dULL, 0x3fefec9a3e778061ULL, 0xbc905e7a108766d1ULL, 0x3fefe315e86e7f85ULL,
  0x3c8cd2523567f613ULL, 0x3fefd9b0d3158574ULL, 0xbc8bce8023f98efaULL, 0x3fefd06b29ddf6deULL,
  0x3c60f74e61e6c861ULL, 0x3fefc74518759bc8ULL, 0x3c90a3e45b33d399ULL, 0x3fefbe3ecac6f383ULL,
  0x3c979aa65d837b6dULL, 0x3fefb5586cf9890fULL, 0x3c8eb51a92fdeffcULL, 0x3fefac922b7247f7ULL,
  0x3c3ebe3d702f9cd1ULL, 0x3fefa3ec32d3d1a2ULL, 0xbc6a033489906e0bULL, 0x3fef9b66affed31bULL,
  0xbc9556522a2fbd0eULL, 0x3fef9301d0125b51ULL, 0xbc5080ef8c4eea55ULL, 0x3fef8abdc06c31ccULL,
  0xbc91c923b9d5f416ULL, 0x3fef829aaea92de0ULL, 0x3c80d3e3e95c55afULL, 0x3fef7a98c8a58e51ULL,
  0xbc801b15eaa59348ULL, 0x3fef72b83c7d517bULL, 0xbc8f1ff055de323dULL, 0x3fef6af9388c8deaULL,
  0x3c8b898c3f1353bfULL, 0x3fef635beb6fcb75ULL, 0xbc96d99c7611eb26ULL, 0x3fef5be084045cd4ULL,
  0x3c9aecf73e3a2f60ULL, 0x3fef54873168b9aaULL, 0xbc8fe782cb86389dULL, 0x3fef4d5022fcd91dULL,
  0x3c8a6f4144a6c38dULL, 0x3fef463b88628cd6ULL, 0x3c807a05b0e4047dULL, 0x3fef3f49917ddc96ULL,
  0x3c968efde3a8a894ULL, 0x3fef387a6e756238ULL, 0x3c875e18f274487dULL, 0x3fef31ce4fb2a63fULL,
  0x3c80472b981fe7f2ULL, 0x3fef2b4565e27cddULL, 0xbc96b87b3f71085eULL, 0x3fef24dfe1f56381ULL,
  0x3c82f7e16d09ab31ULL, 0x3fef1e9df51fdee1ULL, 0xbc3d219b1a6fbffaULL, 0x3fef187fd0dad990ULL,
  0x3c8b3782720c0ab4ULL, 0x3fef1285a6e4030bULL, 0x3c6e149289cecb8fULL, 0x3fef0cafa93e2f56ULL,
  0x3c834d754db0abb6ULL, 0x3fef06fe0a31b715ULL, 0x3c864201e2ac744cULL, 0x3fef0170fc4cd831ULL,
  0x3c8fdd395dd3f84aULL, 0x3feefc08b26416ffULL, 0xbc86a3803b8e5b04ULL, 0x3feef6c55f929ff1ULL,
  0xbc924aedcc4b5068ULL, 0x3feef1a7373aa9cbULL, 0xbc9907f81b512d8eULL, 0x3feeecae6d05d866ULL,
  0xbc71d1e83e9436d2ULL, 0x3feee7db34e59ff7ULL, 0xbc991919b3ce1b15ULL, 0x3feee32dc313a8e5ULL,
  0x3c859f48a72a4c6dULL, 0x3feedea64c123422ULL, 0xbc9312607a28698aULL, 0x3feeda4504ac801cULL,
  0xbc58a78f4817895bULL, 0x3feed60a21f72e2aULL, 0xbc7c2c9b67499a1bULL, 0x3feed1f5d950a897ULL,
  0x3c4363ed60c2ac11ULL, 0x3feece086061892dULL, 0x3c9666093b0664efULL, 0x3feeca41ed1d0057ULL,
  0x3c6ecce1daa10379ULL, 0x3feec6a2b5c13cd0ULL, 0x3c93ff8e3f0f1230ULL, 0x3feec32af0d7d3deULL,
  0x3c7690cebb7aafb0ULL, 0x3feebfdad5362a27ULL, 0x3c931dbdeb54e077ULL, 0x3feebcb299fddd0dULL,
  0xbc8f94340071a38eULL, 0x3feeb9b2769d2ca7ULL, 0xbc87deccdc93a349ULL, 0x3feeb6daa2cf6642ULL,
  0xbc78dec6bd0f385fULL, 0x3feeb42b569d4f82ULL, 0xbc861246ec7b5cf6ULL, 0x3feeb1a4ca5d920fULL,
  0x3c93350518fdd78eULL, 0x3feeaf4736b527daULL, 0x3c7b98b72f8a9b05ULL, 0x3feead12d497c7fdULL,
  0x3c9063e1e21c5409ULL, 0x3feeab07dd485429ULL, 0x3c34c7855019c6eaULL, 0x3feea9268a5946b7ULL,
  0x3c9432e62b64c035ULL, 0x3feea76f15ad2148ULL, 0xbc8ce44a6199769fULL, 0x3feea5e1b976dc09ULL,
  0xbc8c33c53bef4da8ULL, 0x3feea47eb03a5585ULL, 0xbc845378892be9aeULL, 0x3feea34634ccc320ULL,
  0xbc93cedd78565858ULL, 0x3feea23882552225ULL, 0x3c5710aa807e1964ULL, 0x3feea155d44ca973ULL,
  0xbc93b3efbf5e2228ULL, 0x3feea09e667f3bcdULL, 0xbc6a12ad8734b982ULL, 0x3feea012750bdabfULL,
  0xbc6367efb86da9eeULL, 0x3fee9fb23c651a2fULL, 0xbc80dc3d54e08851ULL, 0x3fee9f7df9519484ULL,
  0xbc781f647e5a3ecfULL, 0x3fee9f75e8ec5f74ULL, 0xbc86ee4ac08b7db0ULL, 0x3fee9f9a48a58174ULL,
  0xbc8619321e55e68aULL, 0x3fee9feb564267c9ULL, 0x3c909ccb5e09d4d3ULL, 0x3feea0694fde5d3fULL,
  0xbc7b32dcb94da51dULL, 0x3feea11473eb0187ULL, 0x3c94ecfd5467c06bULL, 0x3feea1ed0130c132ULL,
  0x3c65ebe1abd66c55ULL, 0x3feea2f336cf4e62ULL, 0xbc88a1c52fb3cf42ULL, 0x3feea427543e1a12ULL,
  0xbc9369b6f13b3734ULL, 0x3feea589994cce13ULL, 0xbc805e843a19ff1eULL, 0x3feea71a4623c7adULL,
  0xbc94d450d872576eULL, 0x3feea8d99b4492edULL, 0x3c90ad675b0e8a00ULL, 0x3feeaac7d98a6699ULL,
  0x3c8db72fc1f0eab4ULL, 0x3feeace5422aa0dbULL, 0xbc65b6609cc5e7ffULL, 0x3feeaf3216b5448cULL,
  0x3c7bf68359f35f44ULL, 0x3feeb1ae99157736ULL, 0xbc93091fa71e3d83ULL, 0x3feeb45b0b91ffc6ULL,
  0xbc5da9b88b6c1e29ULL, 0x3feeb737b0cdc5e5ULL, 0xbc6c23f97c90b959ULL, 0x3feeba44cbc8520fULL,
  0xbc92434322f4f9aaULL, 0x3feebd829fde4e50ULL, 0xbc85ca6cd7668e4bULL, 0x3feec0f170ca07baULL,
  0x3c71affc2b91ce27ULL, 0x3feec49182a3f090ULL, 0x3c6dd235e10a73bbULL, 0x3feec86319e32323ULL,
  0xbc87c50422622263ULL, 0x3feecc667b5de565ULL, 0x3c8b1c86e3e231d5ULL, 0x3feed09bec4a2d33ULL,
  0xbc91bbd1d3bcbb15ULL, 0x3feed503b23e255dULL, 0x3c90cc319cee31d2ULL, 0x3feed99e1330b358ULL,
  0x3c8469846e735ab3ULL, 0x3feede6b5579fdbfULL, 0xbc82dfcd978e9db4ULL, 0x3feee36bbfd3f37aULL,
  0x3c8c1a7792cb3387ULL, 0x3feee89f995ad3adULL, 0xbc907b8f4ad1d9faULL, 0x3feeee07298db666ULL,
  0xbc55c3d956dcaebaULL, 0x3feef3a2b84f15fbULL, 0xbc90a40e3da6f640ULL, 0x3feef9728de5593aULL,
  0xbc68d6f438ad9334ULL, 0x3feeff76f2fb5e47ULL, 0xbc91eee26b588a35ULL, 0x3fef05b030a1064aULL,
  0x3c74ffd70a5fddcdULL, 0x3fef0c1e904bc1d2ULL, 0xbc91bdfbfa9298acULL, 0x3fef12c25bd71e09ULL,
  0x3c736eae30af0cb3ULL, 0x3fef199bdd85529cULL, 0x3c8ee3325c9ffd94ULL, 0x3fef20ab5fffd07aULL,
  0x3c84e08fd10959acULL, 0x3fef27f12e57d14bULL, 0x3c63cdaf384e1a67ULL, 0x3fef2f6d9406e7b5ULL,
  0x3c676b2c6c921968ULL, 0x3fef3720dcef9069ULL, 0xbc808a1883ccb5d2ULL, 0x3fef3f0b555dc3faULL,
  0xbc8fad5d3ffffa6fULL, 0x3fef472d4a07897cULL, 0xbc900dae3875a949ULL, 0x3fef4f87080d89f2ULL,
  0x3c74a385a63d07a7ULL, 0x3fef5818dcfba487ULL, 0xbc82919e2040220fULL, 0x3fef60e316c98398ULL,
  0x3c8e5a50d5c192acULL, 0x3fef69e603db3285ULL, 0x3c843a59ac016b4bULL, 0x3fef7321f301b460ULL,
  0xbc82d52107b43e1fULL, 0x3fef7c97337b9b5fULL, 0xbc892ab93b470dc9ULL, 0x3fef864614f5a129ULL,
  0x3c74b604603a88d3ULL, 0x3fef902ee78b3ff6ULL, 0x3c83c5ec519d7271ULL, 0x3fef9a51fbc74c83ULL,
  0xbc8ff7128fd391f0ULL, 0x3fefa4afa2a490daULL, 0xbc8dae98e223747dULL, 0x3fefaf482d8e67f1ULL,
  0x3c8ec3bc41aa2008ULL, 0x3fefba1bee615a27ULL, 0x3c842b94c3a9eb32ULL, 0x3fefc52b376bba97ULL,
  0x3c8a64a931d185eeULL, 0x3fefd0765b6e4540ULL, 0xbc8e37bae43be3edULL, 0x3fefdbfdad9cbe14ULL,
  0x3c77893b4d91cd9dULL, 0x3fefe7c1819e90d8ULL, 0x3c5305c14160cc89ULL, 0x3feff3c22b8f71f1ULL};
static double word (uint64_t w) { double d; memcpy (&d, &w, 8); return d; }
static uint64_t bits (double d) { uint64_t w; memcpy (&w, &d, 8); return w; }
#define OFF 0x3fe6955500000000ULL
static double log_inline (uint64_t ix, double *tail)
{
  uint64_t tmp = ix - OFF, iz;
  int i = (tmp >> 45) % 128, k = (int) ((int64_t) tmp >> 52);
  double z, kd, invc = word (L[3 * i]), logc = word (L[3 * i + 1]), logctail = word (L[3 * i + 2]);
  double r, t1, t2, lo1, lo2, ar, ar2, ar3, hi, lo3, lo4, lo, y;
  iz = ix - (tmp & 0xfffULL << 52);
  z = word (iz);
  kd = (double) k;
#if FUSED
  r = fma (z, invc, -1.0);
  t1 = fma (kd, word (LN2[0]), logc);
  t2 = t1 + r;
  lo1 = fma (kd, word (LN2[1]), logctail);
  lo2 = (t1 - t2) + r;
  ar = word (A[0]) * r;
  ar2 = r * ar;
  ar3 = r * ar2;
  hi = t2 + ar2;
  lo3 = fma (ar, r, -ar2);
  lo4 = (t2 - hi) + ar2;
  lo = fma (ar3, fma (ar2, fma (ar2, fma (r, word (A[6]), word (A[5])), fma (r, word (A[4]), word (A[3]))), fma (r, word (A[2]), word (A[1]))),
            ((lo1 + lo2) + lo3) + lo4);
#else
  {
    double zhi = word ((iz + (1ULL << 31)) & (-1ULL << 32)), zlo = z - zhi;
    double rhi = zhi * invc - 1.0, rlo = zlo * invc, arhi, arhi2, p;
    r = rhi + rlo;
    t1 = kd * word (LN2[0]) + logc;
    t2 = t1 + r;
    lo1 = kd * word (LN2[1]) + logctail;
    lo2 = (t1 - t2) + r;
    ar = word (A[0]) * r;
    ar2 = r * ar;
    ar3 = r * ar2;
    arhi = word (A[0]) * rhi;
    arhi2 = rhi * arhi;
    hi = t2 + arhi2;
    lo3 = rlo * (ar + arhi);
    lo4 = (t2 - hi) + arhi2;
    p = ar3 * ((word (A[1]) + r * word (A[2])) + ar2 * ((word (A[3]) + r * word (A[4])) + ar2 * (word (A[5]) + r * word (A[6]))));
    lo = (((lo1 + lo2) + lo3) + lo4) + p;
  }
#endif
  y = hi + lo;
  *tail = (hi - y) + lo;
  return y;
}
static double exp_inline (double x, double xtail, uint32_t sign_bias, int *refused)
{
  uint32_t abstop = (bits (x) >> 52) & 0x7ff;
  uint64_t ki, idx, sbits;
  double kd, r, r2, tail, tmp, scale;
  if (abstop - 0x3c9 >= 0x3f)
    {
      if (abstop - 0x3c9 >= 0x80000000)
        {
          double one = 1.0 + x;
          return sign_bias ? -one : one;
        }
      *refused = 1;
      return 0.0;
    }
#if FUSED
  kd = fma (word (E[0]), x, word (E[1]));
#else
  kd = word (E[0]) * x + word (E[1]);
#endif
  ki = bits (kd);
  kd -= word (E[1]);
#if FUSED
  r = fma (kd, word (E[3]), fma (kd, word (E[2]), x));
#else
  r = (x + kd * word (E[2])) + kd * word (E[3]);
#endif
  r += xtail;
  idx = 2 * (ki % 128);
  tail = word (T[idx]);
  sbits = T[idx + 1] + ((ki + sign_bias) << 45);
  r2 = r * r;
#if FUSED
  tmp = fma (fma (r, word (C[3]), word (C[2])), r2 * r2, fma (fma (r, word (C[1]), word (C[0])), r2, tail + r));
#else
  tmp = ((tail + r) + r2 * (word (C[0]) + r * word (C[1]))) + (r2 * r2) * (word (C[2]) + r * word (C[3]));
#endif
  scale = word (sbits);
  return MADD (scale, tmp, scale);
}
/* 0: y is not an integer; 1: an odd one; 2: an even one. */
static int checkint (uint64_t iy)
{
  int e = iy >> 52 & 0x7ff;
  if (e < 0x3ff) return 0;
  if (e > 0x3ff + 52) return 2;
  if (iy & ((1ULL << (0x3ff + 52 - e)) - 1)) return 0;
  if (iy & (1ULL << (0x3ff + 52 - e))) return 1;
  return 2;
}
static int zeroinfnan (uint64_t i) { return 2 * i - 1 >= 2 * 0x7ff0000000000000ULL - 1; }
static int signaling (uint64_t i) { return 2 * (i ^ 0x0008000000000000ULL) > 2 * 0x7ff8000000000000ULL; }
double MODEL_POW (double x, double y, int *refused)
{
  uint32_t sign_bias = 0, topx, topy;
  uint64_t ix = bits (x), iy = bits (y);
  double hi, lo, ehi, elo;
  *refused = 0;
  topx = ix >> 52;
  topy = iy >> 52;
  if (topx - 0x001 >= 0x7ff - 0x001 || (topy & 0x7ff) - 0x3be >= 0x43e - 0x3be)
    {
      if (signaling (ix) || signaling (iy)) { *refused = 1; return 0.0; }
      if (zeroinfnan (iy))
        {
          if (2 * iy == 0) return 1.0;
          if (ix == 0x3ff0000000000000ULL) return 1.0;
          if (2 * ix > 2 * 0x7ff0000000000000ULL || 2 * iy > 2 * 0x7ff0000000000000ULL) return x + y;
          if (2 * ix == 2 * 0x3ff0000000000000ULL) return 1.0;
          if ((2 * ix < 2 * 0x3ff0000000000000ULL) == !(iy >> 63)) return 0.0;
          return y * y;
        }
      if (zeroinfnan (ix))
        {
          double x2 = x * x;
          if (ix >> 63 && checkint (iy) == 1) x2 = -x2;
          return iy >> 63 ? 1 / x2 : x2;
        }
      if (ix >> 63)
        {
          int yint = checkint (iy);
          if (yint == 0) return (x - x) / (x - x);
          if (yint == 1) sign_bias = 0x800 << 7;
          ix &= 0x7fffffffffffffffULL;
          topx &= 0x7ff;
        }
      if ((topy & 0x7ff) - 0x3be >= 0x43e - 0x3be)
        {
          if (ix == 0x3ff0000000000000ULL) return 1.0;
          if ((topy & 0x7ff) < 0x3be) return ix > 0x3ff0000000000000ULL ? 1.0 + y : 1.0 - y;
          *refused = 1;                                       /* an overflow or an underflow */
          return 0.0;
        }
      if (topx == 0)
        {
          ix = bits (word (ix) * 0x1p52);
          ix &= 0x7fffffffffffffffULL;
          ix -= 52ULL << 52;
        }
    }
  hi = log_inline (ix, &lo);
#if FUSED
  ehi = y * hi;
  elo = fma (y, lo, fma (y, hi, -ehi));
#else
  {
    double yhi = word (iy & -1ULL << 27), ylo = y - yhi;
    double lhi = word (bits (hi) & -1ULL << 27), llo = (hi - lhi) + lo;
    ehi = yhi * lhi;
    elo = ylo * lhi + y * llo;
  }
#endif
  return exp_inline (ehi, elo, sign_bias, refused);
}
