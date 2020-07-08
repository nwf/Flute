// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved.
// DO NOT EDIT! This file is automatically generated from a script

// Size, type and function declarations for cache structures

package Cache_Decls_RV64_8KB_2way;

// ================================================================
// Basic sizes, from which everything else is derived

// Bits_per_PA       = 64    (= 0x40)    (bits per physical addr)
// KB_per_Cache      =  8    (= 0x08)    (cache size)
// Word64s_per_CLine =  8    (= 0x08)    (cache line size in word64s)
// Ways_per_CSet     =  2    (= 0x02)    (associativity)

// ================================================================
// Type decls

// Cache Lines ----------------

typedef         8   Word64s_per_CLine;    // (basic)
typedef         3   Bits_per_Word64_in_CLine;    // log2 (Word64s_per_CLine)

typedef        64   Bytes_per_CLine;    // Word64s_per_CLine * Bytes_per_Word64
typedef         6   Bits_per_Byte_in_CLine;    // log2 (Bytes_per_CLine)

typedef       512   Bits_per_CLine;    // Bytes_per_CLine * 8

// Cache Sets ----------------

typedef         2   Ways_per_CSet;    // (basic; associativity)
typedef         1   Bits_per_Way_in_CSet;    // log2 (Ways_per_CSet)

typedef       128   Bytes_per_CSet;    // Ways_per_CSet * Bytes_per_CLine

// Cache ----------------

typedef         8   KB_per_Cache;    // (basic)
typedef      8192   Bytes_per_Cache;    // KB_per_Cache * 1024
typedef      1024   Word64s_per_Cache;    // Bytes_per_Cache / Bytes_per_Word64
typedef       128   CLines_per_Cache;    // Bytes_per_Cache / Bytes_per_CLine

typedef        64   CSets_per_Cache;    // Bytes_per_Cache / Bytes_per_CSet
typedef         6   Bits_per_CSet_in_Cache;    // log2 (CSets_per_Cache)

typedef       512   CSet_Word64s_per_Cache;    // CSets_per_Cache * Word64s_per_CLine
typedef         9   Bits_per_CSet_Word64_in_Cache;    // Bits_per_CSet_in_Cache + Bits_per_Word64_in_CLine
typedef        52   Bits_per_CTag;    // Bits_per_PA - (Bits_per_CSet_in_Cache + Bits_per_Byte_in_CLine)

// ================================================================
// Integer decls

// Cache Lines ----------------

Integer             word64s_per_cline =        8;    // (basic)
Integer      bits_per_word64_in_cline =        3;    // log2 (Word64s_per_CLine)

Integer               bytes_per_cline =       64;    // Word64s_per_CLine * Bytes_per_Word64
Integer        bits_per_byte_in_cline =        6;    // log2 (Bytes_per_CLine)

Integer                bits_per_cline =      512;    // Bytes_per_CLine * 8

// Cache Sets ----------------

Integer                 ways_per_cset =        2;    // (basic; associativity)
Integer          bits_per_way_in_cset =        1;    // log2 (Ways_per_CSet)

Integer                bytes_per_cset =      128;    // Ways_per_CSet * Bytes_per_CLine

// Cache ----------------

Integer                  kb_per_cache =        8;    // (basic)
Integer               bytes_per_cache =     8192;    // KB_per_Cache * 1024
Integer             word64s_per_cache =     1024;    // Bytes_per_Cache / Bytes_per_Word64
Integer              clines_per_cache =      128;    // Bytes_per_Cache / Bytes_per_CLine

Integer               csets_per_cache =       64;    // Bytes_per_Cache / Bytes_per_CSet
Integer        bits_per_cset_in_cache =        6;    // log2 (CSets_per_Cache)

Integer        cset_word64s_per_cache =      512;    // CSets_per_Cache * Word64s_per_CLine
Integer  bits_per_cset_word64_in_cache =        9;    // Bits_per_CSet_in_Cache + Bits_per_Word64_in_CLine
Integer                 bits_per_ctag =       52;    // Bits_per_PA - (Bits_per_CSet_in_Cache + Bits_per_Byte_in_CLine)

// Addrs ----------------

Integer       addr_lo_word64_in_cline =        3;    // addr_hi_byte_in_word64 + 1
Integer       addr_hi_word64_in_cline =        5;    // addr_lo_word64_in_cline + Bits_per_Word64_in_CLine - 1

Integer         addr_lo_cset_in_cache =        6;    // addr_hi_word64_in_cline + 1
Integer         addr_hi_cset_in_cache =       11;    // addr_lo_cset_in_cache + Bits_per_CSet_in_Cache - 1

Integer  addr_lo_cset_word64_in_cache =        3;    // addr_hi_byte_in_word64 + 1
Integer  addr_hi_cset_word64_in_cache =       11;    // addr_lo_cset_word64_in_cache + Bits_per_CSet_Word64_in_Cache - 1

Integer                  addr_lo_ctag =       12;    // addr_hi_cset_in_cache + 1

// ================================================================
// Addresses and address-fields

// Local synonyms (for use in this package)
typedef Bit #(Bits_per_CLine)                     CLine;
typedef Bit #(Bits_per_CTag)                      CTag;
typedef Bit #(Bits_per_Byte_in_CLine)             Byte_in_CLine;
typedef Bit #(Bits_per_Word64_in_CLine)           Word64_in_CLine;
typedef Bit #(Bits_per_Way_in_CSet)               Way_in_CSet;
typedef Bit #(Bits_per_CSet_in_Cache)             CSet_in_Cache;
typedef Bit #(Bits_per_CSet_Word64_in_Cache)      CSet_Word64_in_Cache;

// ================================================================
// Address-decode functions

function  Bit #(3)  fn_Addr_to_Byte_in_Word64 (Bit #(n)  addr);
   return  addr [2:0];
endfunction

function  Word64_in_CLine  fn_Addr_to_Word64_in_CLine (Bit #(n)  addr);
   return  addr [addr_hi_word64_in_cline : addr_lo_word64_in_cline ];
endfunction

function  CSet_in_Cache  fn_Addr_to_CSet_in_Cache (Bit #(n)  addr);
   return  addr [addr_hi_cset_in_cache : addr_lo_cset_in_cache ];
endfunction

function  CSet_Word64_in_Cache  fn_Addr_to_CSet_Word64_in_Cache (Bit #(n)  addr);
   return  addr [addr_hi_cset_word64_in_cache : addr_lo_cset_word64_in_cache ];
endfunction

function  CTag  fn_PA_to_CTag (Bit #(n)  pa);
   return  pa [(valueOf (n) - 1) : addr_lo_ctag ];
endfunction

// Align to start of CLine
function  Bit #(n)  fn_align_Addr_to_CLine (Bit #(n)  addr);
   Bit #(n) mask = (1 << addr_lo_cset_in_cache) - 1;
   return  addr & (~ mask);
endfunction

// ================================================================

endpackage: Cache_Decls_RV64_8KB_2way
