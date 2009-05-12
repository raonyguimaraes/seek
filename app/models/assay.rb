class Assay < ActiveRecord::Base  

  has_and_belongs_to_many :studies
  has_and_belongs_to_many :sops
  
  belongs_to :assay_type
  belongs_to :technology_type

  validates_presence_of :title
  validates_uniqueness_of :title

  validates_presence_of :assay_type
  validates_presence_of :technology_type

  acts_as_solr(:fields=>[:description,:title],:include=>[:assay_type,:technology_type]) if SOLR_ENABLED
  
  def short_description
    type=assay_type.nil? ? "No type" : assay_type.title
    
    "#{title} (#{type})"
  end

end
