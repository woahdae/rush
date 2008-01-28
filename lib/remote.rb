module Rush
	module Connection
		class Remote
			attr_reader :host

			def initialize(host)
				@host = host
			end

			def write_file(full_path, contents)
				transmit(:action => 'write_file', :full_path => full_path, :payload => contents)
			end

			def file_contents(full_path)
				transmit(:action => 'file_contents', :full_path => full_path)
			end

			def destroy(full_path)
				transmit(:action => 'destroy', :full_path => full_path)
			end

			def transmit(params)
				require 'net/http'
				Net::HTTP.start(host, 9000) do |http|
					payload = params.delete(:payload)
					uri = "/?"
					params.each do |key, value|
						uri += "#{key}=#{value}&"
					end
					res = http.post(uri, payload)
					res.body
				end
			end
		end
	end
end