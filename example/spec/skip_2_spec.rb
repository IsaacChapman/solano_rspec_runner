describe "example pending spec 2" do
  it "should be pending" do
    if defined? skip
      skip
    else
      pending
    end
  end
end
