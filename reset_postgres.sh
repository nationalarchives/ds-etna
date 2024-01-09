#!/bin/bash

docker-compose exec postgres dropdb -U etna etna && createdb -U etna etna
