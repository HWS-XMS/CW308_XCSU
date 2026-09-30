import sys
import numpy as np
import matplotlib.pyplot as plt
from Crypto.Cipher import AES

from cw308_xcsu_aes import BUILD, CW308XCSU

NTRACES = 250

KEY = bytes([0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
             0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c])
PT  = bytes([0x32, 0x43, 0xf6, 0xa8, 0x88, 0x5a, 0x30, 0x8d,
             0x31, 0x31, 0x98, 0xa2, 0xe0, 0x37, 0x07, 0x34])
CT  = bytes([0x39, 0x25, 0x84, 0x1d, 0x02, 0xdc, 0x09, 0xfb,
             0xdc, 0x11, 0x85, 0x97, 0x19, 0x6a, 0x0b, 0x32])

with CW308XCSU() as dut:
    if "--program" in sys.argv:
        dut.program()
        print("device programmed")

    print(f"clk {dut.clk/1e6:.1f} MHz  adc {dut.adc_freq/1e6:.1f} MHz  "
          f"gain {dut.gain_db} dB  samples {dut.samples}")

    dut.set_key(KEY)

    got = dut.encrypt(PT)
    if got != CT:
        print(f"known answer FAILED: got {got.hex()} expected {CT.hex()}")
        sys.exit(1)
    print(f"known answer OK: {got.hex()}")

    cipher = AES.new(KEY, AES.MODE_ECB)
    rng = np.random.default_rng(0)
    traces, bad = [], 0

    while len(traces) < NTRACES:
        pt = bytes(rng.integers(0, 256, 16, dtype=np.uint8))
        wave, ct = dut.capture(pt)
        if wave is None or ct != cipher.encrypt(pt):
            bad += 1
            if bad > NTRACES // 4:
                break
        else:
            traces.append(wave)

t = np.array(traces)
print(f"{len(t)} verified traces, {bad} rejected, {t.shape[1]} samples")
print(f"peak {np.max(np.abs(t)):.3f} ({100*np.max(np.abs(t))/0.5:.0f}% of full scale)")
print(f"variance peaks at sample {int(np.argmax(t.var(axis=0)))}")

fig, ax = plt.subplots(2, 1, figsize=(12, 7), sharex=True)
ax[0].plot(t.mean(axis=0), linewidth=0.8)
ax[0].set_ylabel("mean")
ax[0].grid(alpha=0.3)
ax[1].plot(t.var(axis=0), linewidth=0.8, color="tab:green")
ax[1].set_ylabel("variance")
ax[1].set_xlabel("sample")
ax[1].grid(alpha=0.3)
fig.tight_layout()
out = BUILD / "aes_traces.png"
fig.savefig(out, dpi=130)
print(f"wrote {out}")

if "--show" in sys.argv:
    plt.show()
