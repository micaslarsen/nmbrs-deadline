@echo off
setlocal

REM Set default output path to the current directory if not provided
set "output_path=%cd%"
if not [%1]==[] set "output_path=%1"

REM Set default date to today if not provided
set "current_date=%date:~10,4%-%date:~4,2%-%date:~7,2%"
if not [%2]==[] set "current_date=%2"

echo Restoring from backups in %output_path% with date %current_date%...

docker run --rm --volume deadline_docker_db_data:/data --volume "%output_path%":/backup ubuntu tar xvf /backup/deadline_docker_db_%current_date%.tar -C /
docker run --rm --volume deadline_docker_certs:/data --volume "%output_path%":/backup ubuntu tar xvf /backup/deadline_docker_certs_%current_date%.tar -C /
docker run --rm --volume deadline_docker_repo:/data --volume "%output_path%":/backup ubuntu tar xvf /backup/deadline_docker_repo_%current_date%.tar -C /
docker run --rm --volume deadline_docker_server_certs:/data --volume "%output_path%":/backup ubuntu tar xvf /backup/deadline_docker_server_certs_%current_date%.tar -C /

echo Restore complete.