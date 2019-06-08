+++
date = "2019-06-08T13:32:44+01:00"
title = "Load Testing For Everyone"
tags = ["go", "vegeta", "load testing", "reliability", "scalability"]
categories = ["programming"]
draft = false
description = "Load Testing For Everyone"
weight = 10
+++

## What is load testing?
From the [wikipedia](https://en.wikipedia.org/wiki/Load_testing), we have one definition of:

> Load testing is the process of putting demand on a system and
> measuring its response.

This is a pretty straight forward and simple way of putting it, but I like it - throw some load at a service and see what happens. Specifically, when we're talking about load testing HTTP services, some of the things we are looking for are;

1. What are the limits of this system, or where does the system start to degrade in performance? (this could mean anything from increased latency to completely failed requests).
2. What monitors do we need in place so we can be alerted when we approach our limits? (This can include autoscaling thresholds, as we tend to prefer building horizontally scalable systems that ideally can scale without humans being involved).
3. How does the system perform with sustained load over a longer period of time? (These are often the most frustrating issues to track down as they can be non-deterministic or only show themselves in specific environments).

Based on the definition provided above, load testing is quite generic. Depending on what your goals are, you might want to try something like [stress testing](https://www.guru99.com/stress-testing-tutorial.html) or [benchmarking](https://www.guru99.com/benchmark-testing.html). 

## Why we need it

I work as a software engineer at [Deliveroo](https://deliveroo.co.uk/) on the restaurants data team. The company has been growing a lot over the past few years and this means our systems are continually playing keep-up with our traffic. This poses a challenge for building systems that will be able to keep up with future traffic. We can't always accurately predict the expected traffic years out, so when building new systems, we try to take the most conservative approach - build the system for an order of magnitude higher expected traffic. We've recently been writing a lot of our new systems in [Go](https://golang.org/) (previously, we had been writing a lot of Ruby). While we know that Go is significantly more performant than Ruby, we still need a way to verify that our new systems will scale as we expect. 

We'd like to have a solution that makes load testing easy on our engineers. We want to remove adhoc load testing solutions and provide a single tool that hopefully supports the use cases of everyones load testing needs.

Some requirements of the system we needed to build:
* Run within our VPC in AWS.
* Support longevity load tests that run overnight or over the course of multiple days.
* Support custom request bodies with potentially randomly generated values to support a wide range of requests and use cases.
* Allow an engineer to specify the peak Requests Per Second and Duration of the load test and group them together to simulate realistic customer traffic (i.e. 200RPS total for 10 minutes, 50% `GET` requests to `/foo`, 30% `POST` requests to `/foo`, and the remainder `PUT` requests to `/foo/<randomInt>`).
* Support a realistic traffic pattern that our systems tend to experience (we typically have a lunch-time peak followed by an even higher dinner peak).

## Making Load Testing easy

Introducing [Mjölnir](https://en.wikipedia.org/wiki/Mj%C3%B6lnir) - for those that are interested in Norse mythology (or MCU) you might recognize the name. Mjölnir is the name of our load generation service internally because it's meant to Hammer your service. 

It's implemented using [Vegeta](https://github.com/tsenart/vegeta), an open source tool written in Go for generating load. While Vegeta can be used as a powerful command line utility for load testing, we needed something more customizable, so we opted to use Vegeta as a library and build a system around it to enable any engineer to perform load testing of their services in a repeatable and replay-able way and scale to the amount of requests needed to accurately simulate real customer traffic.

There were several challenges involved in building a load testing tool to enable our engineers to perform their own load testing:
1. Vegeta doesn't support a distributed environment as there is no orchestration built into it to support this. 
2. When we started, Vegeta only support a constant request rate. Luckily for us, they've recently added support for a [Sine Pacer](https://github.com/tsenart/vegeta/pull/400) to simulate traffic following a sinusoidal function, which couldn't have come at a more opportune moment.
3. We need a way to allow engineers to define load tests that can be replayed in the future.
4. We need a way for engineers to get the output of their load tests that Vegeta generates so they can perform some analysis.

Our system roughly looks like the following:

![Architecture](/img/mjolnir.png)

In the diagram I've separated out the logical processes of the system, but in reality, a single process is running all of the functionalities at the same time. 

We run the Control Plane as a Goroutine in each process, and we run multiple Workers as Goroutines on the same process as well. We haven't had a need to physically separate these different tasks, as the API and the Control Plane are using very minimal amounts of resources. Having said that, they are designed such that they are independent and there is no IPC coordination between them - they can be separated and the system require no changes.

The Workers are the biggest resources hogs in the system, as they are strictly generating as much load as is requested by the Load Tests. They are network and memory constrained typically, so we've tuned our system to allow us to use the maximum number of file descriptors for opening ports and bumped the memory on the system to accommodate thousands of Requests Per Second on each instance. 

The most interesting piece in the system is the `Control Plane`. The Control Plane is responsible for scheduling the Load Tests onto Workers. It is running a loop that queries the Database for the current state of the Load Tests and takes action if needed - for example, launching a Load Test in a Goroutine or canceling a Load Test if the user has requested that a Load Test be cancelled. 

With this architecture, we can horizontally scale the number of processes we are running and the Load Tests will be optimistically scheduled by each Control Plane process that attempts to claim a Load Test.

You can create a Load Test through the API, but we've recently added a beautiful UI to allow anyone to browse for previously created Load Tests against their services, create new ones or clone existing Load Tests for easy replay-ability and track the progress of their Load Tests.

We allow users to enter their request bodies with a minimal DSL that supports generating data at request time so each request is different. For example, you might tell Mjölnir that your request body should look like:

```
{
    id: <randomInt>
    city: <randomCity>
    name: <randomName>
}
```

and at the time of sending the request we will generate the appropriate random data. This was a commonly requested feature to get around a lot of use cases where perhaps the `name` field is a unique constraint in a database and so all subsequent requests in the Load Tests were not able to accurately perform the workflow of inserting a new item in their database.


## Next Steps

We now have a system that makes load testing incredibly easy. This helps gives confidence to our engineers performing system or software upgrades (like database versions, Go versions, or libraries) or creating new systems/features. We give them the power to perform these load tests themselves in a central place so they can benefit from the experience and work of those that did similarly before them.

There is still plenty of work that we'd like to do to make Mjölnir a more useful tool;

 1. We need to instrument (and load test!) Mjölnir itself so we know it's health and have confidence that the Load Tests we are running are actually running as expected.
 2. We want to add some more intelligence to the Control Plane so that it will only schedule Load Tests if there is enough capacity to actually reach the desired throughput of that Load Test.
 3. We want to be given a traffic profile from our production service and generate load based on the kind of traffic it received during this time window. This would help replicate incident scenarios and allow our engineers to debug in our staging environment to build confidence before shipping their fixes to production. 

If you have any thoughts, ideas, opinions on load testing or things we can improve on, you can reach out to me on [twitter](https://twitter.com/mitchfriedman5).
