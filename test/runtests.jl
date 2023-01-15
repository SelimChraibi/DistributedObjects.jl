using Distributed; addprocs(2)
@everywhere using DistributedObjects
using Test

@testset "DistributedObjects.jl" begin

    do1 = DistributedObject(()->ones(1,1), 2)
    do2 = DistributedObject((pid)->ones(2,2); pids=[1,2])
    do3 = DistributedObject((pid)->ones(3,3))

    @test fetch(@spawnat 2 localpart(do1)==ones(1,1))
    @test fetch(@spawnat 2 localpart(do2)==ones(2,2))  
    @test localpart(do2)==ones(2,2)
    @test fetch(@spawnat 3 localpart(do3)==ones(3,3)) 

    @test try
        fetch(@spawnat 3 localpart(do2))
        false
    catch e 
        true
    end

    close(do1)
    close(do2)
    close(do3)

    @test try
        fetch(@spawnat 3 localpart(do3))
        false
    catch e 
        true
    end
end
