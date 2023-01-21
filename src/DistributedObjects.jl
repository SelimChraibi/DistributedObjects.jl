module DistributedObjects

    using UUIDs
    using Distributed

    export DistributedObject, delete!, close, where

    const objects = Dict{UUID, Any}()

    function add_object(f::Function; return_type=false::Bool)
        uuid = uuid1()
        objects[uuid] = f()
        return_type ? (uuid, typeof(objects[uuid])) : uuid  
    end

    function add_object(f::Function, pid::Int64; return_type=false::Bool)
        pid==myid() && return add_object(f; return_type=return_type)
        remotecall_fetch(add_object, pid, f; return_type=return_type)
    end

    remove_object(uuid::UUID) = delete!(objects, uuid)

    ############################################
    #            DistributedObject
    ############################################
    
    struct DistributedObject{T}
        refs::Dict{Int64,UUID}
        """
            DistributedObject{T}() where T

        Create an empty `DistributedObject` which will reference objects of type `T` stored on remote processes.

        For example, `DistributedObject{Int64}()`, will return a distributed object capable of referencing `Int64` objects.
        """
        DistributedObject{T}() where T = new(Dict{Int64,UUID}())
        
        """
            DistributedObject{T}(f::Function; pids=workers()::Vector{Int64})

        Make a reference to objects of type `T` stored on processes `pids`.
        `f` is a function that when executed on a `pid` in `pids` must return an implementation of an object of type `T`.
        The default `pids` are the worker processes.

        For example, `DistributedObject((pid)->pid * ones(2); pids=[2,3])`, will return a distributed object referencing a vector `[2,2]` and `[3,3]` stored on workers 2 and 3 respectively.
        """
        function DistributedObject(f::Function; pids=workers()::Vector{Int64})
            @assert !isempty(pids) "Please make sure worker process have been launched and provide a non empty `pids`"
            refs = Dict{Int64,UUID}()


            types = Vector{Type}(undef, length(pids))
            @sync for (i,pid) in enumerate(pids)
                @async refs[pid], types[i] = add_object(()->f(pid), pid; return_type=true)
            end
            length(types)==1 || @assert all(==(types[1]), types)
            new{types[1]}(refs)
        end

        """
            DistributedObject{T}(f::Function, pid::Int64)

        Make a reference to an object of type `T` stored on process `pid`.
        `f` is a function that when executed on `pid` must return an implementation of an object of type `T`.

        For example, `DistributedObject(()->ones(2), 4)`, will return a distributed object referencing a vector `[1,1]` stored on workers 4.
        """
        DistributedObject(f::Function, pid::Int64) = DistributedObject((pid)->f(), pids=[pid])
    end

    ############################################
    #                 getindex
    ############################################

    """
        Base.getindex(d::DistributedObject{T}) where T

    Retrieve the object stored by the current process.
    """
    function Base.getindex(d::DistributedObject{T}) where T
        objects[d.refs[myid()]]
    end

    """
        Base.getindex(d::DistributedObject{T}, pid::Int64) where T

    Retrieve the remote object stored at process `pid`.
    """
    function Base.getindex(d::DistributedObject{T}, pid::Int64) where T
        mypid = myid()
        pid==mypid ? objects[d.refs[mypid]] : fetch(@spawnat pid objects[d.refs[pid]])
    end

    """
        Base.getindex(d::DistributedObject{T}, pids::Int64...) where T

    Retrieve the remote object(s) stored at process(es) `pids` if they exist.
    If no `pids` is given, the object stored by the current process is returned.
    Warning: retrieving remote objects will create communication costs.
    """
    function Base.getindex(d::DistributedObject{T}, pids::Int64...) where T
        output = Vector{T}(undef, length(pids))

        for (i, pid) in enumerate(pids)
            @assert haskey(d.refs, pid) "This distributed object has no remote object on process $pid."
            output[i] = d[pid]
        end
        output
    end

    ############################################
    #                 setindex
    ############################################

    """
        Base.setindex!(d::DistributedObject{T}, f::Function) where T

    Store the object of type `T` returned by `f` on the current process. `f` should take no argument.
    """
    function Base.setindex!(d::DistributedObject{T}, f::Function) where T
        mypid = myid()
        haskey(d.refs, mypid) && delete!(d, mypid)
        d.refs[mypid] = add_object(f)
    end

    """
        Base.setindex!(d::DistributedObject{T}, f::Function, pid::Int64) where T

    Store the object of type `T` returned by `f` evaluated on process `pid`. `f` should take no argument.
    """
    function Base.setindex!(d::DistributedObject{T}, f::Function, pid::Int64) where T        
        haskey(d.refs, pid) && delete!(d, pid)
        d.refs[pid] = add_object(f, pid)
    end

    """
        Base.setindex!(d::DistributedObject{T}, f::Function, pids::Int64...) where T

    Store the objects of type `T` returned by `f` evaluated on each process of `pids`. `f` should take a `pid::Int64` as an argument.
    """
    function Base.setindex!(d::DistributedObject{T}, f::Function, pids::Int64...) where T
        for pid in pids
            d[pid] = ()->f(pid)
        end
    end

    """
        Base.setindex!(d::DistributedObject{T}, o::T) where T

    Store the object `o` on the current process.
    """
    function Base.setindex!(d::DistributedObject{T}, o::T) where T
        d[] = ()->o
    end

    """
        Base.setindex!(d::DistributedObject{T}, o::T, pid::Int64) where T

    Store the object `o` on process `pid`.
    """
    function Base.setindex!(d::DistributedObject{T}, o::T, pid::Int64) where T        
        d[pid] = ()->o
    end

    """
        Base.setindex!(d::DistributedObject{T}, os::Vector{T}, pids::Int64...) where T

    Store the objects `os` on the process of `pids`.
    """
    function Base.setindex!(d::DistributedObject{T}, os::Vector{T}, pids::Int64...) where T
        index = Dict{Int64,Int64}(pids .=> 1:length(pids))
        d[pids...] = (pid)->os[index[pid]]
    end

    ############################################
    #            delete and close
    ############################################

    """
        Base.delete!(d::DistributedObject, pid::Int64)

    Remove the remote object stored on process `pid`.
    """
    function Base.delete!(d::DistributedObject, pid::Int64)
        @assert haskey(d.refs, pid) "This distributed object has no remote object on process $pid."
        remote_do(remove_object, pid, d.refs[pid])
        delete!(d.refs, pid)
        return nothing
    end 

    """
        Base.close(d::DistributedObject)

    Remove all the remote objects.
    """
    function Base.close(d::DistributedObject) 
        @sync for pid in keys(d.refs)
            @async remote_do(remove_object, pid, d.refs[pid])
        end     
        empty!(d.refs)
        return nothing
    end 

    ############################################
    #                   others
    ############################################

    Base.eltype(::Type{DistributedObject{T}}) where {T} = T

    where(d::DistributedObject) = sort(collect(keys(d.refs)))
end