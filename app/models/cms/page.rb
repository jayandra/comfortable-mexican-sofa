class Cms::Page < ActiveRecord::Base
  
  set_table_name :cms_pages
  
  # -- AR Extensions --------------------------------------------------------
  acts_as_tree :counter_cache => :children_count
  
  attr_accessor :tags
  
  # -- Relationships --------------------------------------------------------
  belongs_to :site
  belongs_to :layout
  belongs_to :target_page,
    :class_name => 'Cms::Page'
  has_many :blocks,
    :dependent  => :destroy
  accepts_nested_attributes_for :blocks
  
  # -- Callbacks ------------------------------------------------------------
  before_validation :assign_parent,
                    :assign_full_path
  before_validation :assign_position,
                    :on => :create
  before_save :set_cached_content
  after_save  :sync_child_pages
  
  # -- Validations ----------------------------------------------------------
  validates :site_id, 
    :presence   => true
  validates :label,
    :presence   => true
  validates :slug,
    :presence   => true,
    :format     => /^\w[a-z0-9_-]*$/i,
    :unless     => lambda{ |p| p == Cms::Page.root || p.site && p.site.pages.count == 0 }
  validates :layout,
    :presence   => true
  validates :full_path,
    :presence   => true,
    :uniqueness => { :scope => :site_id }
  validate :validate_target_page
  
  # -- Scopes ---------------------------------------------------------------
  default_scope order(:position)
  scope :published, where(:is_published => true)
  
  # -- Class Methods --------------------------------------------------------
  # Tree-like structure for pages
  def self.options_for_select(site, page = nil, current_page = nil, depth = 0, exclude_self = true, spacer = '. . ')
    return [] if (current_page ||= site.pages.root) == page && exclude_self || !current_page
    out = []
    out << [ "#{spacer*depth}#{current_page.label}", current_page.id ] unless current_page == page
    current_page.children.each do |child|
      out += options_for_select(site, page, child, depth + 1, exclude_self, spacer)
    end
    return out.compact
  end
  
  # -- Instance Methods -----------------------------------------------------
  # For previewing purposes sometimes we need to have full_path set
  def full_path
    self.read_attribute(:full_path) || self.assign_full_path
  end
  
  # Transforms existing cms_block information into a hash that can be used
  # during form processing. That's the only way to modify cms_blocks.
  def blocks_attributes
    self.blocks.inject([]) do |arr, block|
      block_attr = {}
      block_attr[:label]    = block.label
      block_attr[:content]  = block.content
      block_attr[:id]       = block.id
      arr << block_attr
    end
  end
  
  # Processing content will return rendered content and will populate 
  # self.cms_tags with instances of CmsTag
  def content(force_reload = false)
    @content = read_attribute(:content)
    @content = nil if force_reload
    @content ||= begin
      self.tags = [] # resetting
      layout ? ComfortableMexicanSofa::Tag.process_content(self, layout.merged_content) : ''
    end
  end
  
  # Array of cms_tags for a page. Content generation is called if forced.
  # These also include initialized cms_blocks if present
  def tags(force_reload = false)
    self.content(true) if force_reload
    @tags ||= []
  end
  
  # Full url for a page
  def url
    "http://#{self.site.hostname}#{self.full_path}"
  end
  
protected
  
  def assign_parent
    return unless site
    self.parent ||= site.pages.root unless self == site.pages.root || site.pages.count == 0
  end
  
  def assign_full_path
    self.full_path = self.parent ? "#{self.parent.full_path}/#{self.slug}".squeeze('/') : '/'
  end
  
  def assign_position
    return unless self.parent
    max = self.parent.children.maximum(:position)
    self.position = max ? max + 1 : 0
  end
  
  def validate_target_page
    return unless self.target_page
    p = self
    while p.target_page do
      return self.errors.add(:target_page_id, 'Invalid Redirect') if (p = p.target_page) == self
    end
  end
  
  def set_cached_content
    write_attribute(:content, self.content(true))
  end
  
  # Forcing re-saves for child pages so they can update full_paths
  def sync_child_pages
    children.each{ |p| p.save! } if full_path_changed?
  end
  
end
