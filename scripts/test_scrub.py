"""Tests for scrub.py, with made-up values in the shapes the lab produces. Run: python3 -m unittest discover scripts"""

import unittest

import scrub


class ScrubTest(unittest.TestCase):
    def setUp(self):
        scrub.mappings.clear()

    def test_vpc_prefix_moves_to_documentation_range_keeping_subnet_and_interface(self):
        out = scrub.scrub("vpc 2600:1f18:abcd:ef00::/56 subnet 2600:1f18:abcd:ef10::/64 host 2600:1f18:abcd:ef10:1:2:3:4")
        self.assertEqual(out, "vpc 2001:db8:1::/56 subnet 2001:db8:1:10::/64 host 2001:db8:1:10:1:2:3:4")

    def test_different_prefixes_get_different_placeholders(self):
        out = scrub.scrub("2600:1f18:abcd:ef10::1 2a04:4e42::223 2600:1f18:abcd:ef11::1")
        self.assertEqual(out, "2001:db8:1:10::1 2001:db8:2::223 2001:db8:1:11::1")

    def test_nat64_address_matches_its_a_record(self):
        out = scrub.scrub("github.com A 140.82.112.3\ngithub.com AAAA 64:ff9b::8c52:7003\n200 via 64:ff9b::8c52:7003")
        self.assertEqual(out, "github.com A 203.0.113.1\ngithub.com AAAA 64:ff9b::203.0.113.1\n"
                              "200 via 64:ff9b::203.0.113.1")

    def test_local_and_well_known_addresses_stay(self):
        text = ("http://[fd00:ec2::254]/latest fe80::1%ens5 ::1 ::/0 64:ff9b::/96 nameserver 169.254.169.253 "
                "10.30.0.5 2001:db8::1")
        self.assertEqual(scrub.scrub(text), text)

    def test_times_and_ports_are_not_addresses(self):
        text = "started 2026-11-15T10:11:12Z at 10:11:12, dns=0.004s, 140.82.112.3:443 ab:cd:ef:01:23:45"
        self.assertEqual(scrub.scrub(text), "started 2026-11-15T10:11:12Z at 10:11:12, dns=0.004s, 203.0.113.1:443 "
                                            "ab:cd:ef:01:23:45")

    def test_trailing_punctuation(self):
        self.assertEqual(scrub.scrub("address 2600:1f18:abcd:ef10::1."), "address 2001:db8:1:10::1.")

    def test_ids_account_and_role(self):
        out = scrub.scrub("arn:aws:sts::123456789012:assumed-role/aws-ipv6-lab-instance/i-0123456789abcdef0 "
                          "i-0123456789abcdef0.ec2.internal eigw-0123456789abcdef0 nat-0123456789abcdef0")
        self.assertEqual(out, "arn:aws:sts::111122223333:assumed-role/EXAMPLE1 i-EXAMPLE1.ec2.internal "
                              "eigw-EXAMPLE1 nat-EXAMPLE1")
        self.assertEqual(scrub.leftovers(out), 0)

    def test_bucket_names_lose_their_random_suffix(self):
        out = scrub.scrub("s3://aws-ipv6-lab-results-0123456789abcdef01/x aws-ipv6-lab-probe-fedcba9876543210ab.s3.us-east-1.amazonaws.com")
        self.assertEqual(out, "s3://aws-ipv6-lab-results-EXAMPLE1/x aws-ipv6-lab-probe-EXAMPLE2.s3.us-east-1.amazonaws.com")
        self.assertEqual(scrub.leftovers(out), 0)

    def test_leftovers_flags_real_ipv6(self):
        self.assertEqual(scrub.leftovers("2600:1f18:abcd:ef10::1"), 1)
        self.assertEqual(scrub.leftovers(scrub.scrub("2600:1f18:abcd:ef10::1")), 0)

    def test_more_than_254_ipv4_addresses_move_on_to_the_next_range(self):
        out = scrub.scrub(" ".join(f"8.8.{i // 250}.{i % 250 + 1}" for i in range(300)))
        last = out.split()
        self.assertEqual(last[253], "203.0.113.254")
        self.assertEqual(last[254], "198.51.100.1")
        self.assertEqual(last[299], "198.51.100.46")
        self.assertEqual(scrub.leftovers(out), 0)


    def test_after_the_documentation_ranges_comes_the_benchmarking_range(self):
        out = scrub.scrub(" ".join(f"8.{i // 250}.0.{i % 250 + 1}" for i in range(770))).split()
        self.assertEqual(out[761], "192.0.2.254")
        self.assertEqual(out[762], "198.18.0.1")
        self.assertEqual(scrub.leftovers(" ".join(out)), 0)


if __name__ == "__main__":
    unittest.main()
