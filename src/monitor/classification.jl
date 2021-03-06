module Classification
    using .Threads

    function func(output_matrix::Array{Float32}, sample_matrix::Array{Float32})
        loss = Threads.Atomic{Int64}(0)
        @threads for i in axes(output_matrix, 2)
            if findmax(output_matrix[:,i])[2]!=findmax(sample_matrix[:,i])[2]
                Threads.atomic_add!(loss, 1)
            end
        end
        return loss[]
    end
end
