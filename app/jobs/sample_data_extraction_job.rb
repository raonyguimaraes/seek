class SampleDataExtractionJob < TaskJob
  queue_as QueueNames::SAMPLES
  def perform(data_file, sample_type, overwrite: false)
    extractor = Seek::Samples::Extractor.new(data_file, sample_type)
    extractor.clear
    extractor.extract(overwrite)
  end

  def task
    arguments[0].sample_extraction_task
  end
end
