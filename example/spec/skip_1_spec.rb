describe "example pending spec 1" do
  it "should be pending" do
    if defined? skip
      skip
    else
      pending
    end
  end
end
