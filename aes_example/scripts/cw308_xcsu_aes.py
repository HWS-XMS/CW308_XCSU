import glob
import pathlib
import shutil
import subprocess
import time

import chipwhisperer as cw

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"

HUSKY_SN = "502032204c5846303230333132313030"

CMD_KEY = 0x6B
CMD_ENC = 0x70


def find_vivado():
    found = shutil.which("vivado")
    if found:
        return found
    candidates = sorted(glob.glob("/opt/Xilinx/*/Vivado/bin/vivado"))
    if not candidates:
        raise RuntimeError("vivado not found on PATH or under /opt/Xilinx")
    return candidates[-1]


class CW308XCSU():

    def __init__(self, sn=HUSKY_SN, clk=10e6, baud=38400, gain_db=40, adc_mul=10, samples=250):
        self.sn         = sn
        self.clk        = clk
        self.baud       = baud
        self.gain_db    = gain_db
        self.adc_mul    = adc_mul
        self.samples    = samples
        self.scope      = None
        self.target     = None

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, *exc):
        self.close()

    def connect(self):
        self.scope = cw.scope(sn=self.sn)

        self.scope.gain.db           = self.gain_db
        self.scope.adc.samples       = self.samples
        self.scope.adc.offset        = 0
        self.scope.adc.presamples    = 0
        self.scope.adc.basic_mode    = "rising_edge"
        self.scope.trigger.module    = "basic"
        self.scope.trigger.triggers  = "tio4"
        self.scope.io.tio1           = "serial_rx"
        self.scope.io.tio2           = "serial_tx"
        self.scope.io.tio3           = "high_z"
        self.scope.io.tio4           = "high_z"
        self.scope.io.pdid           = "high_z"
        self.scope.io.pdic           = "high"
        self.scope.io.hs2            = "clkgen"
        self.scope.io.nrst           = "high"
        self.scope.io.cdc_settings   = 0
        self.scope.clock.clkgen_src  = "system"
        self.scope.clock.clkgen_freq = self.clk
        self.scope.clock.adc_mul     = self.adc_mul
        time.sleep(0.5)

        if not self.scope.clock.clkgen_locked:
            raise RuntimeError("clkgen did not lock")

        self.target                 = cw.target(self.scope, cw.targets.SimpleSerial)
        self.target.baud            = self.baud

        self.reset()
        return self

    @property
    def done(self):
        return bool(self.scope.io.pdid_state)

    @property
    def ninit(self):
        return bool(self.scope.io.tio_states[2])

    def pulse_program(self, width=0.01):
        self.scope.io.pdic = "low"
        time.sleep(width)
        self.scope.io.pdic = "high"
        time.sleep(0.05)

    def _wait(self, want_ninit, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.ninit == want_ninit:
                return True
            time.sleep(0.001)
        return False

    def reset_configuration(self, timeout=1.0):
        self.scope.io.pdic = "low"
        cleared = self._wait(False, timeout)
        self.scope.io.pdic = "high"
        ready = self._wait(True, timeout)
        return cleared and ready and not self.done

    def program(self, image=None):
        image = pathlib.Path(image) if image else BUILD / "AES_TOP.pdi"
        if not image.exists():
            raise FileNotFoundError(f"{image} does not exist, run make first")

        BUILD.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [find_vivado(), "-mode", "batch", "-nojournal", "-notrace",
             "-log", "program.log",
             "-source", str(ROOT / "scripts" / "program.tcl"),
             "-tclargs", str(image)],
            cwd=BUILD, capture_output=True, text=True, timeout=900)

        if "PROGRAM_OK" not in result.stdout:
            raise RuntimeError(f"programming failed, see {BUILD / 'program.log'}")

        if self.target is not None:
            self.reset()
        return self

    def close(self):
        if self.target is not None:
            self.target.dis()
            self.target = None
        if self.scope is not None:
            self.scope.dis()
            self.scope = None

    def reset(self):
        self.scope.io.nrst = "low"
        time.sleep(0.05)
        self.scope.io.nrst = "high"
        time.sleep(0.10)
        self.drain()

    def drain(self):
        while self.target.read(0, timeout=50):
            pass
        self.target.flush()

    def set_key(self, key):
        self.target.write(bytes([CMD_KEY]) + bytes(key))
        time.sleep(0.2)
        self.drain()

    def encrypt(self, plaintext):
        self.target.write(bytes([CMD_ENC]) + bytes(plaintext))
        return self._read_block()

    def capture(self, plaintext):
        self.scope.arm()
        self.target.write(bytes([CMD_ENC]) + bytes(plaintext))
        if self.scope.capture():
            return None, None
        wave = self.scope.get_last_trace()
        return wave, self._read_block()

    def _read_block(self, n=16, timeout=3000):
        resp = self.target.read(n, timeout=timeout)
        return bytes(resp, "latin-1") if isinstance(resp, str) else bytes(resp)

    @property
    def adc_freq(self):
        return self.scope.clock.adc_freq
