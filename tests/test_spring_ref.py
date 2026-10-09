import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spring_ref as ref  # noqa: E402


class ReferenceIsCorrect(unittest.TestCase):
    """The closed form (which SpringMath.js mirrors) must agree with numerical integration."""

    def test_closed_form_matches_rk4(self):
        for k, z in ref.PAIRS:
            for x0, v0, target in ref.STARTS:
                for t in (0.2, 1.0):
                    ax, av = ref.analytic(t, x0, v0, target, k, z)
                    nx, nv = ref.rk4(t, x0, v0, target, k, z, steps=4000)
                    scale = 1 + abs(ax) + abs(av)
                    self.assertAlmostEqual(ax, nx, delta=1e-6 * scale, msg=f"x k={k} z={z} {x0,v0,target} t={t}")
                    self.assertAlmostEqual(av, nv, delta=1e-6 * scale, msg=f"v k={k} z={z} {x0,v0,target} t={t}")

    def test_t_zero_returns_initial_state(self):
        self.assertEqual(ref.analytic(0, 3.0, -2.0, 9.0, 800, 0.6), (3.0, -2.0))

    def test_converges_to_target(self):
        for k, z in ref.PAIRS:
            x, v = ref.analytic(60.0, 5.0, 2.0, -1.0, k, z)
            self.assertAlmostEqual(x, -1.0, places=9)
            self.assertAlmostEqual(v, 0.0, places=9)

    def test_branches_are_continuous_at_critical_damping(self):
        a = ref.analytic(0.1, 0.0, 0.0, 1.0, 600, 1 - 1e-7)
        b = ref.analytic(0.1, 0.0, 0.0, 1.0, 600, 1.0)
        c = ref.analytic(0.1, 0.0, 0.0, 1.0, 600, 1 + 1e-7)
        for u, w in zip(a, b):
            self.assertAlmostEqual(u, w, delta=1e-5)
        for u, w in zip(c, b):
            self.assertAlmostEqual(u, w, delta=1e-5)

    def test_underdamped_overshoots_and_critical_does_not(self):
        peak = lambda k, z: max(ref.analytic(i / 1000, 0, 0, 1, k, z)[0] for i in range(1, 3000))
        self.assertGreater(peak(800, 0.6), 1.05)
        self.assertLessEqual(peak(1600, 1.0), 1 + 1e-12)
        self.assertLessEqual(peak(500, 3.0), 1 + 1e-12)

    def test_case_matrix_size(self):
        self.assertEqual(len(ref.cases()), len(ref.PAIRS) * len(ref.STARTS) * len(ref.TIMES))
        self.assertEqual(len(ref.cases()), 240)


if __name__ == "__main__":
    unittest.main()
