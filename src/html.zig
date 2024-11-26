pub const style_css = @embedFile("style.css");

pub const error_page = "<html><body><style>" ++ style_css ++ "</style><h1>Apologies! An error occurred</h1></body></html>";
