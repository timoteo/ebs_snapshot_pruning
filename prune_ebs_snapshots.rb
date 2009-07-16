#!/usr/bin/env ruby

# A script to prune ebs snaphots.
# Depends on the right_aws gem: 'sudo gem install right_aws'
#
# Author: Timo O'Hara (timo@bizo.com)

require 'rubygems'
require 'right_aws'
require 'date'

# Set the following env variables
aws_access_key_id = ENV['AWS_ACCESS_KEY_ID'] 
aws_secret_access_key = ENV['AWS_SECRET_ACCESS_KEY'] 

# Keeps the most recent 'num_snaps_to_keep' snapshots for the given ebs_snapshots array 
# and deletes the rest.  Does not do anything if there are fewer snapshots than
# 'num_snaps_to_keep'.
def prune_ebs_snapshots(ec2, ebs_snapshots, num_snaps_to_keep)
  # only remove snapshots if we need to 
  if ebs_snapshots.size > num_snaps_to_keep then
    # sort by date from most recent to oldest
    ebs_snapshots.sort! do |a,b| 
      b[:aws_started_at] <=> a[:aws_started_at]
    end

    # grab the snapshots to delete
    snaps_to_delete = ebs_snapshots.slice(num_snaps_to_keep - 1..-1)

    puts "Deleting #{snaps_to_delete.size} snapshots..."
    snaps_to_delete.each do |snapshot| 
      puts "Deleting snapshot [#{snapshot[:aws_id]}] for volume [#{snapshot[:aws_volume_id]}] with creation date: #{snapshot[:aws_started_at]}"
      ec2.delete_snapshot(snapshot[:aws_id])
    end
  end
end

if __FILE__ == $0
  exit_code = 0

  begin
    ec2 = RightAws::Ec2.new(aws_access_key_id, aws_secret_access_key)
    ebs_volumes = ec2.describe_volumes
    ebs_snapshots = ec2.describe_snapshots
    
    # 500 is the AWS default for the number of snapshots you are able to have
    max_ebs_snapshots = 500
    # The % of snapshots to keep per volume.  Change as necessary.
    pct_snapshots_to_keep = 0.40
    
    if ebs_volumes.size > 0 and max_ebs_snapshots == ebs_snapshots.size then
      puts "Total Number of EBS volumes is: #{ebs_volumes.size}"
      puts "Keeping #{pct_snapshots_to_keep * 100}% of snapshots per volume" 
      
      ebs_volumes.each do |ebs_volume|
        ebs_snapshots_for_volume = ebs_snapshots.select do |ebs_snapshot|
          ebs_snapshot[:aws_status] == "completed" and ebs_snapshot[:aws_volume_id] == ebs_volume[:aws_id]
        end
    
        if ebs_snapshots_for_volume.size > 0 then
          num_snaps_to_keep = (pct_snapshots_to_keep * ebs_snapshots_for_volume.size).to_i
          puts "Keeping #{num_snaps_to_keep} snapshots for volume [#{ebs_volume[:aws_id]}]" 
          prune_ebs_snapshots(ec2, ebs_snapshots_for_volume, num_snaps_to_keep)
        else
          puts "Skipping volume [#{ebs_volume[:aws_id]}] as it has no snapshots." 
        end
      end
    else
      puts "Not doing anything as no EBS volumes were found." if ebs_volumes.size == 0
      puts "Not doing anything as max number of EBS snapshots [#{max_ebs_snapshots}] has not been reached.  There are currently #{ebs_snapshots.size} snapshots." if ebs_snapshots.size < max_ebs_snapshots
    end
  rescue RightAws::AwsError => e
    puts "AWS Error occurred"
    e.errors.each do |error|
      puts "code: #{error[0]}, msg: #{error[1]}"
    end
    exit_code = 1
  rescue
    puts "Unexpected Error: #{$ERROR_INFO}"
    exit_code = 2 
  end

  exit exit_code
end
