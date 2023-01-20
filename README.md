# DistributedObjects

[![Build Status](https://github.com/Selim78/DistributedObjects.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Selim78/DistributedObjects.jl/actions/workflows/CI.yml?query=branch%3Amain)


`DistributedObjects.jl` lets you **create**, **access**, **modify** and **delete** remotely stored objects.

## Installation

You can install DistributedObjects by typing

```julia
julia> ] add DistributedObjects
```

## Usage

### 1. Create

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
and let's create an empty `DistributedObject`

```julia
another_distributed_plant = DistributedObject{Plant}() # make sure to specify the type of the objects it'll receive
```

### 2. Access

We can access each plant by passing indexes to the `DistributedObject`s
```julia
distributed_plants[] # [] accesses current process (here 1) returns Plant("peppermint", true)
distributed_plants[1] # returns Plant("peppermint", true)
distributed_plants[4] # returns Plant("hemlock", false)
fetch(@spawnat 4 distributed_plants[]) # returns Plant("hemlock", false)
distributed_plants[1,4] # returns [Plant("peppermint", true), Plant("hemlock", false)]
one_distributed_plant[6] # returns Plant("foxglove", false)
```

**Note:** fetching objects from remote processes is possible, but not recommended if you want to avoid the communication overhead.


### 3. Modify

Let's add some plants to `another_distributed_plant`

```julia
another_distributed_plant[] = ()->Plant("plantain", true) # [] adds a plant at current process (here 1) 
another_distributed_plant[5] = ()->Plant("clover", true)
another_distributed_plant[2,4] = (pid)->Plant(args[pid]...)
```
wait actually I'd rather have `"spearmint"`🌱 at `2`...
```julia
another_distributed_plant[2] = ()->Plant("spearmint", true)
```

Oh, and if you ever forget what type of objects you stored and where you stored them
```julia
eltype(distributed_plants) # returns Plant
where(distributed_plants) # returns [1, 2, 4]
```

### 4. Delete

Once we're done with a plant we can remove it from its `DistibutedObject`
```julia
delete!(distributed_plants, 2)

distributed_plants[2]
# ERROR: On worker 2:
# No localpart on process 2
```


Finally, we clean up after ourselves when we're done with the `DistibutedObject`s

```julia
close(distributed_plants)
close(one_distributed_plant)
close(another_distributed_plant)
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
