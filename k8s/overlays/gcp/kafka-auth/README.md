This is Google's [Managed Kafka local auth server](https://github.com/googleapis/managedkafka)
at commit `96b82c8e6db506515a6751660f71c346e89664cb`, copied under Apache 2.0.
The script SHA-256 is `2fd08a1be5d78944250fac731708612d29064cb461015629fa71b27a08d3c2e0`.
It serves short-lived ADC credentials on pod loopback port 14293. Build and scan it
locally, then publish an immutable digest through a separately authorized release.
The current cloud overlay contains a nonfunctional digest placeholder.
