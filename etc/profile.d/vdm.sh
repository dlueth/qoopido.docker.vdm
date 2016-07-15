alias up='docker-compose up -d --timeout 600 && docker-compose logs';
alias down='docker-compose stop --timeout 600 && docker rm $(docker ps -a -q)';