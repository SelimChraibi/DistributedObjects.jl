# DistributedObjects

[![Build Status](https://github.com/SelimChraibi/DistributedObjects.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/SelimChraibi/DistributedObjects.jl/actions/workflows/CI.yml?query=branch%3Amain) 

Ever had trouble keeping track of objects on remote processes? <br>
`DistributedObjects.jl` lets you [**create**](#1-create), [**access**](#2-access), [**modify**](#3-modify) and [**delete**](#4-delete) remotely stored objects.

## Installation

You can install `DistributedObjects` by typing

```julia
julia> ] add DistributedObjects
```

## Usage

Start with your usual [distributed setup](https://github.com/Arpeggeo/julia-distributed-computing) 

```julia
# launch multiple processes (or remote machines)
using Distributed; addprocs(5)

# instantiate and precompile environment in all processes
@everywhere (using Pkg; Pkg.activate(@__DIR__); Pkg.instantiate(); Pkg.precompile())

# you can now use DistributedObjects
@everywhere using DistributedObjects
```

### 1. Create

Behold, a plant ✨
```julia
@everywhere struct Plant
    name::String
    edible::Bool
end
```
Let's create a remote plant on worker `6`
```julia
🍀 = DistributedObject(()->Plant("clover", true), 6);
```
What about some plants on workers `1`, `2`, `4`, all attached to a single `DistributedObject`?
```julia
args = Dict(1=>("peppermint", true), 
            2=>("nettle", true), 
            4=>("hemlock", false))

# note that by default pids=workers()
🪴 = DistributedObject((pid)->Plant(args[pid]...); pids=[1, 2, 4]);
```
Here we initialize an empty `DistributedObject`

```julia
🌱 = DistributedObject{Plant}() # make sure to specify the type of the objects it'll receive
```

And here's a `DistributedObject{Union{Plant, Int64}}` referencing mutilple types

```julia
🌼1️⃣ = DistributedObject((pid)->(Plant("dandelion", true), 1)[pid]; pids=[1,2])
```

Finally, here we specify that we expect multiple types but initialize with only `Int64`s

```julia
🌸2️⃣ = DistributedObject{Union{Int64, Plant}}(()->2, 2) 
🌺3️⃣ = DistributedObject{Union{Int64, Plant}}((pid)->[42, 24][pid], [2,4]) 
```

### 2. Access

We can access each plant by passing indexes to the `DistributedObject`s
```julia
🪴[] # [] accesses the current process (here 1) returns Plant("peppermint", true)
🪴[1] # returns Plant("peppermint", true)
🪴[4] # returns Plant("hemlock", false)
fetch(@spawnat 4 🪴[]) # returns Plant("hemlock", false)
🪴[1,4] # returns [Plant("peppermint", true), Plant("hemlock", false)]
🍀[6] # returns Plant("clover", true)
```

**Note:** fetching objects from remote processes is possible, but not recommended if you want to avoid the communication overhead.


### 3. Modify

Let's add some plants to `🌱`

```julia
🌱[] = ()->Plant("plantain", true) # [] adds a plant at current process (here 1) 
🌱[5] = ()->Plant("chanterelles", true)
🌱[2,4] = (pid)->Plant(args[pid]...)
```
wait `"chanterelles"` isn't a plant...
```julia
🌱[5] = ()->Plant("spearmint", true)
```
If you're working on the current process, or if you don't mind the communication cost, you can also pass the objects directly instead of functions

```julia
🌱[] = Plant("spinach", true) 
🌱[3,4] = [Plant("chickweed", true), Plant("nettle", true)]
```

Oh, and if you ever forget what type of objects you stored and where you stored them
```julia
eltype(🪴) # returns Plant
where(🪴) # returns [1, 2, 4]
```

### 4. Delete

Once we're done with a plant we can remove it from its `DistibutedObject`
```julia
delete!(🪴, 2)

🪴[2]
# ERROR: On worker 2:
# This distributed object has no remote object on process 2.
```


Finally, we clean up after ourselves when we're done with the `DistibutedObject`s

```julia
close(🪴)
close(🍀)
close(🌱)
close(🌼1️⃣)
close(🌸2️⃣) 
close(🌺3️⃣)
```

---
 **Bonus:** you can check with `varinfo()` that the objects are indeed stored remotely and that they are correctly removed by `close`
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
