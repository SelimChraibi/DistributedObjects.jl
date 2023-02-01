using Distributed; addprocs(5)
@everywhere using DistributedObjects
using Test

@testset "DistributedObjects.jl" begin

    # Creating a DistributedObjects
    do0 = DistributedObject{Vector{Int64}}()
    do1 = DistributedObject{Vector{Int64}}()
    do2 = DistributedObject(()->[2,2,2], 2)
    do3 = DistributedObject((pid)->[pid, pid, pid]) # pids = workers()
    do4 = DistributedObject((pid)->[pid, pid, pid]; pids=[1,2])
    do5 = DistributedObject((pid)->[[2],true][pid]; pids=[1,2]) # multiple types

    # Accessing local and remote elements
    @test fetch(@spawnat 2 do2[]==[2,2,2])
    @test do3[4]==[4,4,4]
    @test do3[2]==[2,2,2]
    @test fetch(@spawnat 2 do4[1,2]==[[1,1,1],[2,2,2]]) 
    @test eltype(do5) == Union{Vector{Int64}, Bool}

    # Adding elements (with functions)
    do1[] = ()->[1,1,1]
    do2[3] = ()->[3,3,3]
    do2[1,4] = (pid)->[pid, pid, pid]

    # Adding elements (without functions)
    do0[] = [1,1,1]
    do0[1] = [0,0,0]
    do0[3] = [3,3,3]
    do0[2,4] = [[2,2,2], [4,4,4]]

    # Check type
    @test eltype(do1) == Vector{Int64}

    # Check location
    @test where(do0) == [1,2,3,4]
    @test where(do1) == [1]
    @test where(do2) == [1,2,3,4]

    # Check value
    @test do0[]==[0,0,0]
    @test do1[]==[1,1,1]
    @test do2[3]==[3,3,3]
    @test fetch(@spawnat 4 do2[4]==[4,4,4])

    # Overwrite an element 
    do2[3]=()->[3,6,3]
    
    @test do2[3]==[3,6,3]

    # Deleting elements
    delete!(do2, 3)

    # Check deletion
    @test try
        do2[3]
        false
    catch e 
        true
    end

    # Closing the DistributedObjects
    close(do1)
    close(do2)
    close(do3)
    close(do4)
    
    @test try
        do2[4]
        false
    catch e 
        true
    end

end
