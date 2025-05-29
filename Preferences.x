#import <Preferences/Preferences.h>

@interface VCAMPrefsListController: PSListController
@end

@implementation VCAMPrefsListController
- (id)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"VCAM" target:self];
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
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
@end 