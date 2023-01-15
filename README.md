# DistributedObjects

[![Build Status](https://github.com/Selim78/DistributedObjects.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Selim78/DistributedObjects.jl/actions/workflows/CI.yml?query=branch%3Amain)


`DistributedObjects.jl` lets you **create**, **access** and **delete** remotely stored objects.

## Usage

```julia
using Distributed; addprocs(5)
@everywhere using .DistributedObjects
```

Behold, a plant 🪴
```julia
@everywhere struct Plant
    name::String
    edible::Bool
end
```
Let's create some plant objects on workers `1`, `2`, `4`
```julia
args = Dict(1=>("peppermint", true), 
            2=>("nettle", true), 
            4=>("hemlock", false))

# note that by default pids=workers()
distributed_plants = DistributedObject((pid)->Plant(args[pid]...); pids=[1, 2, 4]);
```
and on worker `6`
```julia
one_distributed_plant = DistributedObject(()->Plant("foxglove", false), 6);

```
We can access each plant by passing the `DistributedObject`s to `localpart` on the process of our choice
```julia
localpart(distributed_plants) # returns Plant("peppermint", true)
remotecall_fetch(localpart, 4, distributed_plants) # returns Plant("hemlock", false)
remotecall_fetch(localpart, 6, one_distributed_plant) # returns Plant("foxglove", false)
```
Once we're done with our plants we can remove them from their respective process
```julia
close(distributed_plants)
close(one_distributed_plant)

remotecall_fetch(localpart, 4, distributed_plants) 
# ERROR: On worker 4:
# No localpart on process 4
```
---
*Bonus:* you can check with `varinfo()` that the objects are indeed stored remotely and that they are correctly removed by `close`

```julia
using Distributed; addprocs(1)

@everywhere using DistributedObjects
@everywhere using InteractiveUtils
@everywhere @show varinfo()

big_array = DistributedObject(()->ones(1000,1000), 2);
@everywhere @show varinfo()

close(big_array)
@everywhere @show varinfo()
```
