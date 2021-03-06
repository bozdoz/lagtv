require 'zip/zip'

class Replay < ActiveRecord::Base
  belongs_to :category
  belongs_to :user
  has_many :comments, :order => 'created_at DESC'
  attr_accessible :description, :league, :players, :protoss, :terran, :title, :zerg, :replay_file, :category_id, :status, :expansion_pack

  LEAGUES = %w{bronze silver gold platinum diamond master grand_master}
  PLAYERS = %w{1v1 2v2 3v3 4v4 FFA}
  STATUSES = %w{new rejected suggested broadcasted downloaded}
  EXPANSION_PACKS = %w{LotV}
  EXPIRY_DAYS = 14
  WEEKLY_UPLOAD_LIMIT = 3
  CLEAN_REPLAYS_DAYS = 28

  DEFAULT_FILTERS = {
    :page => 1,
    :statuses => %w{new suggested},
    :query => '',
    :league => '',
    :players => '',
    :category_id => '',
    :include_expired => false,
    :rating => '',
    :expansion_pack => ''
  }

  mount_uploader :replay_file, ReplayFileUploader

  validates :replay_file,    :presence => true, :unless => :rejected?
  validates :title,          :presence => true
  validates :category_id,    :presence => true
  validates :user_id,        :presence => true
  validates :expires_at,     :presence => true
  validates :players,        :presence => true, :inclusion => { :in => PLAYERS }
  validates :league,         :presence => true, :inclusion => { :in => LEAGUES }
  validates :status,         :presence => true, :inclusion => { :in => STATUSES }
  validates :expansion_pack, :presence => true
  validate :disallow_3_races_in_1v1

  STATUSES.each do |s|
    define_method "#{s}?" do
      status == s
    end
  end

  def disallow_3_races_in_1v1
    if players == '1v1' && zerg? && terran? && protoss?
      errors.add(:players, "can't have all 3 races in a 1v1 game")
    end
  end

  def expired?
    expires_at < DateTime.now.utc
  end

  def filename
    File.basename(self.replay_file.to_s)
  end

  def formatted_game_length
    Time.at(self.length).gmtime.strftime('%T')
  end

  def update_average_rating
    self.average_rating = self.comments.average(:rating)
    self.save!
  end

  def self.all_paged(options = {})
    options = options.reverse_merge(DEFAULT_FILTERS)

    query = "%#{options[:query]}%"
    replays = self.paginate(:page => options[:page], :per_page => 25).order('created_at DESC')
    replays = replays.where('title ilike ? or description ilike ? or replay_file ilike ?', query, query, query) if options[:query].present?
    replays = replays.where('status in (?)', options[:statuses]) if options[:statuses].present?
    replays = replays.where(:league => options[:league]) if options[:league].present?
    replays = replays.where(:players => options[:players]) if options[:players].present?
    replays = replays.where(:category_id => options[:category_id]) if options[:category_id].present?
    replays = replays.where(:expansion_pack => options[:expansion_pack]) if options[:expansion_pack].present?
    if options[:rating].present?
      if options[:rating].to_i == 0
        replays = replays.where('average_rating = ?', options[:rating])
      else
        replays = replays.where('average_rating >= ?', options[:rating])
      end
    end

    unless options[:include_expired]
      replays = replays.where("expires_at > ?", DateTime.now.utc)
    end

    replays
  end

  def update_game_details_from_replay_file
    begin
      mpq = MPQFile.new(replay_file.current_path)
      self.length = mpq.length_in_game_seconds
      self.version = mpq.version
    rescue
      self.length = 0
      self.version = "unknown"
    end

    self.save!
  end

  def already_commented?(user)
    self.comments.where(:user_id => user.id).count > 0
  end

  def clean
    self.status = 'rejected'
    self.remove_replay_file!
    self.save!
  end

  def mark_as_downloaded(user)
    self.update_attributes(:status => 'downloaded') if user.admin?
  end

  def self.clean_old_replays
    Replay.where("status != 'rejected'").where(["created_at < ?", CLEAN_REPLAYS_DAYS.days.ago]).each do |r|
      r.clean
    end
  end

  def self.zip_replay_files(ids, user)
    replays = self.find(ids).select {|r| r.replay_file.blank? == false}

    buffer = Zip::ZipOutputStream::write_buffer do |zip|
      replays.each do |replay|
        zip.put_next_entry("#{replay.id}-#{replay.filename}")
        zip.write File.read(replay.replay_file.current_path)

        replay.mark_as_downloaded(user)
      end
    end

    buffer.rewind
    return buffer.sysread
  end

  def self.bulk_change_status(ids, new_status)
    replays = self.find(ids)
    replays.each do |replay|
      replay.status = new_status
      replay.save
    end
  end
end
