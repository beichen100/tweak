#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface VCAMRootListController : PSListController
@end

@implementation VCAMRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"VCAM" target:self];
	}

	return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Tạo header view
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 120)];
    
    // Thêm logo
    UIImageView *logoView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    logoView.center = CGPointMake(headerView.bounds.size.width / 2, 40);
    logoView.contentMode = UIViewContentModeScaleAspectFit;
    logoView.image = [UIImage imageWithContentsOfFile:@"/Library/PreferenceBundles/VCAMPrefs.bundle/icon.png"];
    logoView.layer.cornerRadius = 10;
    logoView.clipsToBounds = YES;
    [headerView addSubview:logoView];
    
    // Thêm tiêu đề
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 70, headerView.bounds.size.width, 30)];
    titleLabel.text = @"VCAM - Virtual Camera";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [headerView addSubview:titleLabel];
    
    // Thêm phiên bản
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 95, headerView.bounds.size.width, 20)];
    versionLabel.text = @"Version 1.0.0";
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor grayColor];
    [headerView addSubview:versionLabel];
    
    self.table.tableHeaderView = headerView;
    
    // Thêm nút Apply
    UIBarButtonItem *applyButton = [[UIBarButtonItem alloc] initWithTitle:@"Áp dụng" 
                                                                   style:UIBarButtonItemStylePlain 
                                                                  target:self 
                                                                  action:@selector(applySettings)];
    self.navigationItem.rightBarButtonItem = applyButton;
}

- (void)applySettings {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
                                        CFSTR("com.trizau.sileo.vcam.prefschanged"), 
                                        NULL, 
                                        NULL, 
                                        YES);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"VCAM" 
                                                                  message:@"Cài đặt đã được áp dụng. Khởi động lại SpringBoard để có hiệu lực hoàn toàn." 
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" 
                                                      style:UIAlertActionStyleDefault 
                                                    handler:nil];
    
    UIAlertAction *respring = [UIAlertAction actionWithTitle:@"Khởi động lại SpringBoard" 
                                                      style:UIAlertActionStyleDestructive 
                                                    handler:^(UIAlertAction *action) {
        system("killall -9 SpringBoard");
    }];
    
    [alert addAction:okAction];
    [alert addAction:respring];
    [self presentViewController:alert animated:YES completion:nil];
}

// Mở hướng dẫn sử dụng
- (void)openHelp {
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/trizau/iOS-VCAM"] options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/trizau/iOS-VCAM"]];
    }
}

@end 