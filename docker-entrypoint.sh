#!/bin/bash
set -e

if [ "$1" = "slurmdbd" ]
then
    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Starting the Slurm Database Daemon (slurmdbd) ..."

    {
        . /etc/slurm/slurmdbd.conf
        until echo "SELECT 1" | mysql -h $StorageHost -u$StorageUser -p$StoragePass 2>&1 > /dev/null
        do
            echo "-- Waiting for database to become active ..."
            sleep 2
        done
    }
    echo "-- Database is now active ..."

    exec gosu slurm /usr/sbin/slurmdbd -Dvvv
fi

if [ "$1" = "slurmctld" ]
then
    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Waiting for slurmdbd to become active before starting slurmctld ..."

    until 2>/dev/null >/dev/tcp/slurmdbd/6819
    do
        echo "-- slurmdbd is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmdbd is now active ..."

    echo "---> Starting the Slurm Controller Daemon (slurmctld) ..."
    if /usr/sbin/slurmctld -V | grep -q '17.02' ; then
        exec gosu slurm /usr/sbin/slurmctld -Dvvv
    else
        exec gosu slurm /usr/sbin/slurmctld -i -Dvvv
    fi
fi

if [ "$1" = "slurmd" ]
then
    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Waiting for slurmctld to become active before starting slurmd..."

    until 2>/dev/null >/dev/tcp/slurmctld/6817
    do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmctld is now active ..."

    echo "---> Starting the Slurm Node Daemon (slurmd) ..."
    exec /usr/sbin/slurmd -Dvvv
fi

if [ "$1" = "all" ]
then
    if [ ! -d "/var/lib/mysql/mysql" ]; then 
        echo "DAta directory not populated, initialising db"
        mysql_install_db --user=mysql --ldata=/var/lib/mysql/
    fi

    set -e

    /usr/bin/mysqld_safe &

    sleep 10

    mysql -uroot <<< "
    CREATE DATABASE slurm_acct_db;
    create user 'slurm'@'localhost' IDENTIFIED BY 'password';
    GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
    FLUSH PRIVILEGES;
    "

    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Starting the Slurm Database Daemon (slurmdbd) ..."

    {
        . /etc/slurm/slurmdbd.conf
        until echo "SELECT 1" | mysql -h localhost -u slurm -ppassword
        do
            echo "-- Waiting for database to become active ..."
            sleep 2
        done
    }
    echo "-- Database is now active ..."

    exec gosu slurm /usr/sbin/slurmdbd -Dvvv &

    echo "---> Waiting for slurmdbd to become active before starting slurmctld ..."
    sleep 5

    until nc -zv localhost 6819
    do
        echo "-- slurmdbd is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmdbd is now active ..."

    echo "---> Starting the Slurm Controller Daemon (slurmctld) ..."
    exec gosu slurm /usr/sbin/slurmctld -i -Dvvv &

    echo "---> Waiting for slurmctld to become active before starting slurmd..."
    until nc -zv localhost 6817
    do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmctld is now active ..."

    echo "---> Starting the Slurm Node Daemon (slurmd) ..."
    exec /usr/sbin/slurmd -Dvvv

    sacctmgr add cluster linux
    sacctmgr add account default Cluster=linux
    sacctmgr add user name=sqpc_tech account=default
fi

exec "$@"
