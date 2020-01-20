require 'dotenv/load'
require 'securerandom'

def real?
  ARGV[0] == 'real'
end

def image_tag
   real? ? 'latest' : 'dev'
end

def manifest_name
  real? ? 'manifest.yaml' : 'staging-manifest.yaml'
end

def build_args
	{}
end

def rando(length)
	SecureRandom.hex(length / 2)
end

def clear_cluster
	system "kubectl delete ns/nectar --context=dev"
	system "kubectl delete clusterrole/nectar-cluster-wide-role"
	system "kubectl delete clusterrolebinding/nectar-permissions"
	system "kubectl delete secret mosaic-pg -n nectar"
	system "kubectl delete secret mosaic-backend -n nectar"
end

def create_secret_cmd(name, data)
	as_strings = data.keys.map do |key|
		"--from-literal=#{key}=#{data[key]}"
	end
	"create secret generic #{name} #{as_strings.join(' ')}"
end

def create_secrets	
	pg_secret_data = {'db-user': 'cluster', 'db-password': rando(40)}
	system "kubectl #{create_secret_cmd("mosaic-pg", pg_secret_data)} -n nectar"

	backend_secret_data = {'secret-key-base': rando(32), 'attr-encrypt-key': rando(128)}
	system "kubectl #{create_secret_cmd("mosaic-backend", backend_secret_data)} -n nectar"	
end

def build(repo)
	args = build_args[repo.to_sym] || {}
	fmt_args = args.keys.map {|k| "--build-arg #{k}=#{args[k]}"}
	args_str = fmt_args.join(' ')	
	system "cd ./../#{repo} && docker build . #{args_str} -t xnectar/#{repo}:#{image_tag}"
end

def push(repo)
	system "docker push xnectar/#{repo}:#{image_tag}"
end

def update_all
	%w[frontend kapi backend].each do |repo|
		build(repo)
		push(repo)
	end
end

def apply_manifest
	system "kubectl apply -f #{manifest_name}"
end

def port_forward
	system "kill -9 $(lsof -t -i:9000)"
	system "kill -9 $(lsof -t -i:5000)"
	system "kill -9 $(lsof -t -i:3000)"
	Thread.new { system "kubectl port-forward svc/frontend 9000:80 -n nectar" }
	Thread.new { system "kubectl port-forward svc/kapi 5000:5000 -n nectar" }
	Thread.new { system "kubectl port-forward svc/backend 3000:3000 -n nectar" }
end

update_all unless real?
clear_cluster
sleep(5)
apply_manifest
create_secrets
#port_forward


