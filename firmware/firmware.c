#include <stdint.h>

#include <stddef.h>
/* The app SRAM macro has no byte write-enable, so word stores are the only
   efficient way into RAM.  Take a word path whenever both pointers are aligned;
   everything this firmware copies (uint32_t test vectors, 128-bit blocks) is. */
void *memcpy(void *d, const void *s, size_t n) {
  uint8_t *dd = (uint8_t *)d;
  const uint8_t *ss = (const uint8_t *)s;
  if ((((uintptr_t)dd | (uintptr_t)ss) & 3u) == 0u) {
    uint32_t *dw = (uint32_t *)d;
    const uint32_t *sw = (const uint32_t *)s;
    while (n >= 4u) {
      *dw++ = *sw++;
      n -= 4u;
    }
    dd = (uint8_t *)dw;
    ss = (const uint8_t *)sw;
  }
  while (n--)
    *dd++ = *ss++;
  return d;
}
void *memset(void *d, int c, size_t n) {
  uint8_t *dd = (uint8_t *)d;
  if (((uintptr_t)dd & 3u) == 0u) {
    uint32_t w = (uint32_t)(uint8_t)c;
    uint32_t *dw = (uint32_t *)d;
    w |= w << 8;
    w |= w << 16;
    while (n >= 4u) {
      *dw++ = w;
      n -= 4u;
    }
    dd = (uint8_t *)dw;
  }
  while (n--)
    *dd++ = (uint8_t)c;
  return d;
}

#define OUTBYTE (*(volatile uint32_t *)0x10000000)
#define UART_TX (*(volatile uint32_t *)0x10000004)
#define UART_ST (*(volatile uint32_t *)0x1000000C)

/* AEAD Unified Wrapper (base 0x3000_0000). This cluster wires only
 * TinyJAMBU, Xoodyak and GIFT-COFB (see rtl/crypto/crypto_cluster.v) —
 * no ChaCha20-Poly1305, so there is no KEYHI register here. */
#define AEAD_BASE 0x30000000
#define AEAD_REG(off) (*(volatile uint32_t *)(AEAD_BASE + (off)))

#define AEAD_CTRL      AEAD_REG(0x00)
#define AEAD_KEY(i)    AEAD_REG(0x04 + (i) * 4)
#define AEAD_NONCE(i)  AEAD_REG(0x14 + (i) * 4)
#define AEAD_AD(i)     AEAD_REG(0x24 + (i) * 4)
#define AEAD_DIN(i)    AEAD_REG(0x34 + (i) * 4)
#define AEAD_TAGIN(i)  AEAD_REG(0x44 + (i) * 4)

#define AEAD_AD_LEN    AEAD_REG(0x54)
#define AEAD_DAT_LEN   AEAD_REG(0x58)
#define AEAD_MSG_LEN   AEAD_REG(0x5C)

#define AEAD_DOUT(i)       AEAD_REG(0x80 + (i) * 4)
#define AEAD_TAGOUT(i)     AEAD_REG(0x90 + (i) * 4)
#define AEAD_STREAM_STATUS AEAD_REG(0x60)
#define AEAD_STREAM_CTRL   AEAD_REG(0x64)

#define AEAD_ST_GIFT_DATA_VALID  0x01
#define AEAD_ST_GIFT_MSG_REQ     0x02
#define AEAD_ST_GIFT_AD_REQ      0x04

#define AEAD_CTRL_CLR_DATA_VALID 0x04
#define AEAD_CTRL_AD_ACK         0x02
#define AEAD_CTRL_MSG_ACK        0x01

/* ---- UART / console ---- */
void pc(char c) {
  if (c == '\n') {
    while (!(UART_ST & 1))
      ;
    UART_TX = '\r';
  }
  while (!(UART_ST & 1))
    ;
  UART_TX = c;
}

void ps(const char *s) {
  while (*s)
    pc(*s++);
}
void ph(uint32_t v) {
  static const char h[] = "0123456789abcdef";
  for (int i = 28; i >= 0; i -= 4)
    pc(h[(v >> i) & 0xF]);
}
/* Print a 128-bit field stored REGISTER-order (w[0] = hardware LSW,
 * w[3] = MSW) in natural MSB-first hex — used by Xoodyak/GIFT-COFB,
 * whose C-side arrays already mirror the register layout. */
void p128(const uint32_t w[4]) {
  ph(w[3]);
  ph(w[2]);
  ph(w[1]);
  ph(w[0]);
}
/* Print exactly nbytes bytes from a NATURAL-order word array (w[0] = MSW,
 * no zero pad) — used by TinyJAMBU, whose C-side arrays are written
 * human-MSB-first and reversed only at the register write. */
void pbytes_nat(const uint32_t *w, uint32_t nbytes) {
  const char h[] = "0123456789abcdef";
  for (uint32_t b = 0; b < nbytes; b++) {
    uint8_t byte = (uint8_t)(w[b >> 2] >> (8u * (3u - (b & 3u))));
    pc(h[(byte >> 4) & 0xF]);
    pc(h[byte & 0xF]);
  }
}

static void aead_read_data_block(uint32_t w[4]) {
  w[0] = AEAD_DOUT(0);
  w[1] = AEAD_DOUT(1);
  w[2] = AEAD_DOUT(2);
  w[3] = AEAD_DOUT(3);
}

static void aead_read_tag_block(uint32_t w[4]) {
  w[0] = AEAD_TAGOUT(0);
  w[1] = AEAD_TAGOUT(1);
  w[2] = AEAD_TAGOUT(2);
  w[3] = AEAD_TAGOUT(3);
}

static int eq128(const uint32_t a[4], const uint32_t b[4]) {
  return (a[0] == b[0]) && (a[1] == b[1]) && (a[2] == b[2]) && (a[3] == b[3]);
}

static int eq128_masked(const uint32_t a[4], const uint32_t b[4],
                        uint32_t word0_mask) {
  return ((a[0] & word0_mask) == (b[0] & word0_mask)) && (a[1] == b[1]) &&
         (a[2] == b[2]) && (a[3] == b[3]);
}

static int allzero(const uint32_t *w, int n) {
  for (int i = 0; i < n; i++)
    if (w[i])
      return 0;
  return 1;
}

static void aead_clear_data_valid(void) {
  AEAD_STREAM_CTRL = AEAD_CTRL_CLR_DATA_VALID;
}

static void aead_gift_ack_ad(void) { AEAD_STREAM_CTRL = AEAD_CTRL_AD_ACK; }

static void aead_gift_ack_msg(void) { AEAD_STREAM_CTRL = AEAD_CTRL_MSG_ACK; }

/* Generic single-shot AEAD transaction shared by TinyJAMBU and Xoodyak
 * (GIFT-COFB needs its own streaming handshake, see gift_cofb_run below).
 * Writes key/nonce/ad/data(+tag_in for decrypt), starts the op, waits for
 * done, then reads back data_out/tag_out. Returns the final AEAD_CTRL
 * value so the caller can read valid/err.
 *
 * idx_rev: TinyJAMBU's C-side arrays are natural (MSB-first) order, so
 * its register index must be reversed on write/read (word0 of the array
 * maps to the hardware's HIGH word). Xoodyak already stores data in
 * register (LSW-first) order, so idx_rev=0 for it.
 * nonce_words/tag_words: field width differs per core (TinyJAMBU: 3-word
 * nonce, 2-word tag; Xoodyak: 4-word nonce, 4-word tag). */
static uint32_t aead_run(uint32_t alg, int decrypt, int idx_rev,
                         const uint32_t *key,
                         const uint32_t *nonce, int nonce_words,
                         const uint32_t *ad, uint32_t adlen,
                         const uint32_t *din, uint32_t dlen,
                         const uint32_t *tag_in, int tag_words,
                         uint32_t *dout, uint32_t *tagout) {
  int i;
  for (i = 0; i < 4; i++)
    AEAD_KEY(idx_rev ? 3 - i : i) = key[i];
  for (i = 0; i < nonce_words; i++)
    AEAD_NONCE(idx_rev ? nonce_words - 1 - i : i) = nonce[i];
  for (i = 0; i < 4; i++)
    AEAD_AD(idx_rev ? 3 - i : i) = ad[i];
  for (i = 0; i < 4; i++)
    AEAD_DIN(idx_rev ? 3 - i : i) = din[i];
  if (tag_in)
    for (i = 0; i < tag_words; i++)
      AEAD_TAGIN(idx_rev ? tag_words - 1 - i : i) = tag_in[i];
  AEAD_AD_LEN  = adlen;
  AEAD_DAT_LEN = dlen;
  AEAD_CTRL = ((uint32_t)(decrypt != 0) << 3) | (1u << 2) | alg;
  while (!(AEAD_CTRL & 0x40))
    ;
  if (dout)
    for (i = 0; i < 4; i++)
      dout[i] = AEAD_DOUT(idx_rev ? 3 - i : i);
  if (tagout)
    for (i = 0; i < tag_words; i++)
      tagout[i] = AEAD_TAGOUT(idx_rev ? tag_words - 1 - i : i);
  return AEAD_CTRL;
}

/* GIFT-COFB streaming transaction (2-block AD + 2-block MSG shape of
 * KAT #579: 17B AD, 17B MSG). ad0/msg0 are the first 16-byte block;
 * ad1/msg1 are the second (1-byte, left-justified) block, sent only
 * once the core raises its ad_req/msg_req handshake bit mid-operation.
 * tag_in is used only for decrypt (pass NULL for encrypt). Returns the
 * final AEAD_CTRL value; got0/got1 report whether each data_out block
 * was captured (GIFT-COFB streams plaintext/ciphertext out block-by-
 * block, before its own tag check, so unlike the other cores its
 * data_out is not hidden on a failed decrypt — only the final valid bit
 * tells the caller whether to trust it). */
static uint32_t gift_cofb_run(int decrypt, const uint32_t key[4],
                              const uint32_t nonce[4], const uint32_t ad0[4],
                              const uint32_t ad1[4], const uint32_t msg0[4],
                              const uint32_t msg1[4], const uint32_t tag_in[4],
                              uint32_t out0[4], uint32_t out1[4],
                              uint32_t tag[4], int *got0, int *got1) {
  uint32_t status;
  int ad_sent = 0, msg_sent = 0, i;

  *got0 = 0;
  *got1 = 0;
  aead_clear_data_valid();
  for (i = 0; i < 4; i++) AEAD_KEY(i) = key[i];
  for (i = 0; i < 4; i++) AEAD_NONCE(i) = nonce[i];
  for (i = 0; i < 4; i++) AEAD_AD(i) = ad0[i];
  for (i = 0; i < 4; i++) AEAD_DIN(i) = msg0[i];
  if (tag_in)
    for (i = 0; i < 4; i++) AEAD_TAGIN(i) = tag_in[i];
  AEAD_AD_LEN  = 17u;
  AEAD_MSG_LEN = 17u;
  AEAD_CTRL = ((uint32_t)(decrypt != 0) << 3) | (1u << 2) | 2u;

  while (!(AEAD_CTRL & 0x40)) {
    status = AEAD_STREAM_STATUS;
    if ((status & AEAD_ST_GIFT_DATA_VALID) && !*got0) {
      aead_read_data_block(out0);
      *got0 = 1;
      aead_clear_data_valid();
    } else if ((status & AEAD_ST_GIFT_DATA_VALID) && !*got1) {
      aead_read_data_block(out1);
      *got1 = 1;
      aead_clear_data_valid();
    }
    if ((status & AEAD_ST_GIFT_AD_REQ) && !ad_sent) {
      for (i = 0; i < 4; i++) AEAD_AD(i) = ad1[i];
      aead_gift_ack_ad();
      ad_sent = 1;
    }
    if ((status & AEAD_ST_GIFT_MSG_REQ) && !msg_sent) {
      for (i = 0; i < 4; i++) AEAD_DIN(i) = msg1[i];
      aead_gift_ack_msg();
      msg_sent = 1;
    }
  }
  status = AEAD_STREAM_STATUS;
  if ((status & AEAD_ST_GIFT_DATA_VALID) && !*got1) {
    aead_read_data_block(out1);
    *got1 = 1;
    aead_clear_data_valid();
  }
  aead_read_tag_block(tag);
  return AEAD_CTRL;
}

/* ====================================================
 * CORE 1: TinyJAMBU-128 AEAD
 * NIST LWC Msg 9 (AD=12B, MSG=12B), unpadded, natural-order:
 *   key  = 899CD0F7C88A9CDD405D3CCD628D2DDB
 *   npub = 535E438A89158AF8D7F6659B
 *   ad   = 49A44D0EF0AC0C0EF1C0D2B4
 *   pt   = 3BF1A7D289F0E4353CDB944B
 *   ct   = 73C2C23AF3BEB3F2F04D0F20
 *   tag  = E0D0722E1DEC6827
 * ==================================================== */
void test_tinyjambu(int *pass) {
  static const uint32_t key[4]  = {0x899CD0F7, 0xC88A9CDD, 0x405D3CCD, 0x628D2DDB};
  static const uint32_t nonce[3]= {0x535E438A, 0x89158AF8, 0xD7F6659B};
  static const uint32_t ad[4]   = {0x49A44D0E, 0xF0AC0C0E, 0xF1C0D2B4, 0x00000000};
  static const uint32_t pt[4]   = {0x3BF1A7D2, 0x89F0E435, 0x3CDB944B, 0x00000000};
  static const uint32_t ect[4]  = {0x73C2C23A, 0xF3BEB3F2, 0xF04D0F20, 0x00000000};
  static const uint32_t etag[2] = {0xE0D0722E, 0x1DEC6827};
  uint32_t ct[4], tag[4] = {0}, dec[4];
  uint32_t tag_tamper[2], dout2[4], tagout2[4] = {0};
  int enc_ok, dec_ok, tamper_ok;

  ps("========================================\n");
  ps("[CORE 1] TinyJAMBU-128 AEAD (NIST LWC Msg 9, AD=12B, MSG=12B)\n");
  ps("========================================\n");
  ps("Input:\n");
  ps("Key          : "); pbytes_nat(key, 16); pc('\n');
  ps("Nonce        : "); pbytes_nat(nonce, 12); pc('\n');
  ps("AD           : "); pbytes_nat(ad, 12); pc('\n');
  ps("Plaintext    : "); pbytes_nat(pt, 12); pc('\n');

  ps("Output (Encrypt):\n");
  aead_run(0u, 0, 1, key, nonce, 3, ad, 12u, pt, 12u, NULL, 2, ct, tag);
  enc_ok = eq128(ct, ect) && tag[0] == etag[0] && tag[1] == etag[1];
  ps("Ciphertext   : "); pbytes_nat(ct, 12); pc('\n');
  ps("Tag          : "); pbytes_nat(tag, 8); pc('\n');
  ps("ENCRYPT      : "); ps(enc_ok ? "PASS\n" : "FAIL\n");

  ps("Output (Decrypt):\n");
  aead_run(0u, 1, 1, key, nonce, 3, ad, 12u, ct, 12u, tag, 2, dec, NULL);
  dec_ok = (AEAD_CTRL & 0x80) && eq128(dec, pt);
  ps("Decrypted    : "); pbytes_nat(dec, 12); pc('\n');
  ps("Valid        : "); pc((AEAD_CTRL & 0x80) ? '1' : '0'); pc('\n');
  ps("DECRYPT      : "); ps(dec_ok ? "PASS\n" : "FAIL\n");

  tag_tamper[0] = tag[0] ^ 1u;
  tag_tamper[1] = tag[1];
  aead_run(0u, 1, 1, key, nonce, 3, ad, 12u, ct, 12u, tag_tamper, 2,
          dout2, tagout2);
  tamper_ok = !(AEAD_CTRL & 0x80) && allzero(dout2, 4) && allzero(tagout2, 2);
  ps("Tamper check : tag bit flipped -> Valid=");
  pc((AEAD_CTRL & 0x80) ? '1' : '0');
  ps(tamper_ok ? "  PASS\n" : "  FAIL\n");

  ps("----------------------------------------\n");
  *pass = enc_ok && dec_ok && tamper_ok;
  ps(*pass ? "TinyJAMBU : PASS\n\n" : "TinyJAMBU : FAIL\n\n");
}

/* ====================================================
 * CORE 2: Xoodyak (NIST LWC Finalist KAT Count 472: AD=9B, PT=14B)
 * pt[0] byte 14 (0x0e) is intentionally non-zero past data_length (14B)
 * to exercise the core's length masking of trailing message bytes.
 * ==================================================== */
void test_xoodyak(int *pass) {
  static const uint32_t key[4]   = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  static const uint32_t nonce[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  static const uint32_t ad[4]    = {0x00000000, 0x08000000, 0x04050607, 0x00010203};
  static const uint32_t pt[4]    = {0x0c0d0e00, 0x08090a0b, 0x04050607, 0x00010203};
  static const uint32_t ect[4]   = {0x93090000, 0x6b339d70, 0x24fb2cc1, 0x76e90670};
  static const uint32_t etag[4]  = {0x25016E36, 0x0DC1F1C9, 0x717ED777, 0x572A92E7};
  uint32_t ct[4], tag[4], dec[4];
  uint32_t tag_tamper[4], dout2[4] = {0}, tagout2[4] = {0};
  int enc_ok, dec_ok, tamper_ok;

  ps("========================================\n");
  ps("[CORE 2] Xoodyak AEAD (NIST LWC finalist KAT Count 472, AD=9B, MSG=14B)\n");
  ps("========================================\n");
  ps("Input:\n");
  ps("Key          : "); p128(key); pc('\n');
  ps("Nonce        : "); p128(nonce); pc('\n');
  ps("AD           : "); p128(ad); pc('\n');
  ps("Plaintext    : "); p128(pt); pc('\n');

  ps("Output (Encrypt):\n");
  aead_run(1u, 0, 0, key, nonce, 4, ad, 9u, pt, 14u, NULL, 4, ct, tag);
  enc_ok = eq128_masked(ct, ect, 0xFFFF0000) && eq128(tag, etag);
  ps("Ciphertext   : "); p128(ct); pc('\n');
  ps("Tag          : "); p128(tag); pc('\n');
  ps("ENCRYPT      : "); ps(enc_ok ? "PASS\n" : "FAIL\n");

  ps("Output (Decrypt):\n");
  aead_run(1u, 1, 0, key, nonce, 4, ad, 9u, ct, 14u, tag, 4, dec, NULL);
  dec_ok = (AEAD_CTRL & 0x80) && eq128_masked(dec, pt, 0xFFFF0000);
  ps("Decrypted    : "); p128(dec); pc('\n');
  ps("Valid        : "); pc((AEAD_CTRL & 0x80) ? '1' : '0'); pc('\n');
  ps("DECRYPT      : "); ps(dec_ok ? "PASS\n" : "FAIL\n");

  tag_tamper[0] = tag[0] ^ 1u;
  tag_tamper[1] = tag[1];
  tag_tamper[2] = tag[2];
  tag_tamper[3] = tag[3];
  aead_run(1u, 1, 0, key, nonce, 4, ad, 9u, ct, 14u, tag_tamper, 4,
          dout2, tagout2);
  tamper_ok = !(AEAD_CTRL & 0x80) && allzero(dout2, 4) && allzero(tagout2, 4);
  ps("Tamper check : tag bit flipped -> Valid=");
  pc((AEAD_CTRL & 0x80) ? '1' : '0');
  ps(tamper_ok ? "  PASS\n" : "  FAIL\n");

  ps("----------------------------------------\n");
  *pass = enc_ok && dec_ok && tamper_ok;
  ps(*pass ? "Xoodyak   : PASS\n\n" : "Xoodyak   : FAIL\n\n");
}

/* ====================================================
 * CORE 3: GIFT-COFB — multi-block KAT #579 (AD=17B, PT=17B), exercises
 * the req/ack streaming handshake (2 AD blocks + 2 MSG blocks).
 * ==================================================== */
void test_giftcofb(int *pass) {
  static const uint32_t key[4]  = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  static const uint32_t nonce[4]= {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  static const uint32_t ad0[4]  = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  static const uint32_t ad1[4]  = {0x00000000, 0x00000000, 0x00000000, 0x10000000};
  static const uint32_t ct0_exp[4] = {0xda23161c, 0x824effe3, 0xb7680d22, 0x54b63042};
  static const uint32_t ct1_exp[4] = {0x00000000, 0x00000000, 0x00000000, 0x2d000000};
  static const uint32_t tag_exp[4] = {0x9c079228, 0xa0da3055, 0xb0433543, 0x82c5c511};
  uint32_t out0[4], out1[4] = {0}, tag[4] = {0};
  uint32_t dec0[4], dec1[4] = {0};
  uint32_t tag_tamper[4], dout2a[4] = {0}, dout2b[4] = {0}, tagout2[4] = {0};
  int got0, got1, enc_ok, dec_ok, tamper_ok;
  uint32_t ctrl;

  ps("========================================\n");
  ps("[CORE 3] GIFT-COFB AEAD (KAT #579, multi-block, AD=17B, MSG=17B)\n");
  ps("========================================\n");
  ps("Input:\n");
  ps("Key          : "); p128(key); pc('\n');
  ps("Nonce        : "); p128(nonce); pc('\n');
  ps("AD (17B)     : "); p128(ad0); ph(ad1[3]); pc('\n');
  ps("MSG (17B)    : "); p128(ad0); ph(ad1[3]); pc('\n');

  ps("Output (Encrypt):\n");
  ctrl = gift_cofb_run(0, key, nonce, ad0, ad1, ad0, ad1, NULL, out0, out1,
                       tag, &got0, &got1);
  (void)ctrl;
  ps("CT blk0      : "); p128(out0); pc('\n');
  ps("CT blk1      : "); ph(out1[3]); pc('\n');
  ps("Tag          : "); p128(tag); pc('\n');
  enc_ok = got0 && got1 && eq128(out0, ct0_exp) && eq128(out1, ct1_exp) &&
          eq128(tag, tag_exp);
  ps("ENCRYPT      : "); ps(enc_ok ? "PASS\n" : "FAIL\n");

  ps("Output (Decrypt):\n");
  ctrl = gift_cofb_run(1, key, nonce, ad0, ad1, ct0_exp, ct1_exp, tag_exp,
                       dec0, dec1, tag, &got0, &got1);
  ps("PT blk0      : "); p128(dec0); pc('\n');
  ps("PT blk1      : "); ph(dec1[3]); pc('\n');
  ps("Valid        : "); pc((ctrl & 0x80) ? '1' : '0'); pc('\n');
  dec_ok = (ctrl & 0x80) && got0 && got1 && eq128(dec0, ad0) && eq128(dec1, ad1);
  ps("DECRYPT      : "); ps(dec_ok ? "PASS\n" : "FAIL\n");

  tag_tamper[0] = tag_exp[0] ^ 1u;
  tag_tamper[1] = tag_exp[1];
  tag_tamper[2] = tag_exp[2];
  tag_tamper[3] = tag_exp[3];
  ctrl = gift_cofb_run(1, key, nonce, ad0, ad1, ct0_exp, ct1_exp, tag_tamper,
                       dout2a, dout2b, tagout2, &got0, &got1);
  tamper_ok = !(ctrl & 0x80) && allzero(tagout2, 4);
  ps("Tamper check : tag bit flipped -> Valid=");
  pc((ctrl & 0x80) ? '1' : '0');
  ps(tamper_ok ? "  PASS\n" : "  FAIL\n");

  ps("----------------------------------------\n");
  *pass = enc_ok && dec_ok && tamper_ok;
  ps(*pass ? "GIFT-COFB : PASS\n\n" : "GIFT-COFB : FAIL\n\n");
}

/* ====================================================
 * MAIN
 * ==================================================== */
int main(void) {
  OUTBYTE = 0x01;
  for (volatile int i = 0; i < 500000; i++)
    ;

  int jb_pass = 0, xd_pass = 0, gc_pass = 0;

  ps("\n\n");
  ps("# ======================================\n");
  ps("# PicoRV32 Crypto SoC - AEAD cluster @ 0x3000_0000\n");
  ps("# Core 1: TinyJAMBU   Core 2: Xoodyak   Core 3: GIFT-COFB\n");
  ps("# ======================================\n\n");

  test_tinyjambu(&jb_pass);
  ps("\n");
  test_xoodyak(&xd_pass);
  ps("\n");
  test_giftcofb(&gc_pass);
  ps("\n");

  ps("# ======================================\n");
  int all = jb_pass && xd_pass && gc_pass;
  if (all) {
    ps("# RESULT: ALL CRYPTO CORES PASS\n");
    OUTBYTE = 0xFF;
  } else {
    ps("# RESULT: SOME TESTS FAILED\n");
    if (!jb_pass)
      ps("#   TinyJAMBU: FAIL\n");
    if (!xd_pass)
      ps("#   Xoodyak:   FAIL\n");
    if (!gc_pass)
      ps("#   GIFT-COFB: FAIL\n");
    OUTBYTE = 0x55;
  }
  ps("# ======================================\n");
  while (1)
    ;
}
