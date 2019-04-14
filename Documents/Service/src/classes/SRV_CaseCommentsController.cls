public class SRV_CaseCommentsController {
    /*
Method Name : getCaseComments
Purpose     : To get the Case Comments
*/
    @AuraEnabled
    public static list<SFDC_Service_Timecard__c> getCaseComments(String CaseID, string CaseCommentID, list<string> lstCommentType){
        //We must revise this method to handle Case Comments without time log as well. Not urgent for the demo
        string CommentType = '';
        system.debug('entered the method'+CaseID+'---CaseCommentID---'+CaseCommentID);
        //Get the Time log data based on the Case ID and CommentType, if any
        string strTimeCardsQuery = 'select id, Case__c, createdDate, createdby.name,CommentType__c, Date_of_Service__c, Hours_Worked__c, Comments__c,  ' +
            'CaseCommentID__c, CreatedbyID, User__c, User__r.Name from SFDC_Service_Timecard__c where Case__c = :CaseID';        
        
        if(!lstCommentType.isempty()){
            strTimeCardsQuery = strTimeCardsQuery + ' and CommentType__c IN :lstCommentType';
        }
        
        if (CaseCommentID != '')            
            strTimeCardsQuery = strTimeCardsQuery + ' and Id = :CaseCommentID';
        
        strTimeCardsQuery = strTimeCardsQuery + ' Order By Createddate desc';
        system.debug('Time Log query is ' + strTimeCardsQuery);
        //Get the Time log data based on the Case ID and CommentType, if any
        list<sObject> lstTimeLogs = Database.query(strTimeCardsQuery);
        
        system.debug('Time Log query is ' + lstTimeLogs);
        return (list<SFDC_Service_Timecard__c>) lstTimeLogs;
    }
    
    @AuraEnabled
    public static user getUserName() {
        User objUser = [select id,Name from User where id =: userInfo.getUserId()];
        return objUser;
    }
    
    @AuraEnabled
    public static list<user> getServiceTechnician(String searchStr){   
        
        string strSearch = '%' + searchStr + '%';
        List<user> lstUser = [Select Id, Name from user where 
                              isActive = true and 
                              (name like : strSearch)];
        system.debug('lstUser--'+lstUser);
        return lstUser;
    }
    
    @AuraEnabled
    public static AuraProcessingMessage CreateCaseComments(SFDC_Service_Timecard__c timelogobj)
    {  
        system.debug('--timelogobj--'+timelogobj);
        //I HAVE COMMENTED THE CASE COMMENT CREATION ON TIME LOG INSERT IN SRV CASE HANDLER - WE WILL NEED TO CONFIRM IF IT IS STILL REQUIRED. 
        //
        AuraProcessingMessage objReturn = new AuraProcessingMessage();
        try
        {
            string strBody = timelogobj.Comments__c; //TO BE DELETED AFTER THE HUB CHANGE
            timelogobj.Service_Note__c = strBody.stripHtmlTags(); //TO BE DELETED AFTER THE HUB CHANGE
            upsert timelogobj;               
            if(timelogobj != null && timelogobj.CaseCommentID__c != null){
                CaseComment objCM = new CaseComment();
                objCM.Id  = timelogobj.CaseCommentID__c;
                if (strBody.length()>3500)
                    strBody = strBody.substring(0,3500); 
                objCM.CommentBody = strBody;
                Update objCM;
            }
            /*if(timelogobj.CommentType__c == 'RFO Description')
{
Case objcase = new case();
objcase.RFO_Description__c = timelogobj.Comments__c;
//objcase.Latest_Case_Status__c = timelogobj.Comments__c;
objcase.id = timelogobj.Case__c;
update objcase;
}*/
            objReturn.isSuccess = true;
        }
        catch (exception e)
        {
            objReturn.isSuccess = false;
            objReturn.errorMsg = e.getMessage();
            string excepMsg = e.getMessage();
            string strMsg = 'STRING_TOO_LONG';
            if(excepMsg.contains('STRING_TOO_LONG'))
            throw new AuraHandledException('Exception:STRING_TOO_LONG');
            else
                throw new AuraHandledException('Exception: '+ excepMsg);
        }
        return objReturn;           
    }
    
     /*
* Name: SendCaseCommentNotification
* Description : Sends notification to the receipients listed in custom setting if the case status is changed/Time log is created
* Parameters : @lstCases : List of Case Id's /List of Time log ID's
*              @NotificationType : Email template for Time Log creation /Case Status updation
*/
    @InvocableMethod(label='Send Case Notifications')
    public static void SendCaseNotification(list<Case> lstCases) {
        try{
            //Notifications on Case
            list<Messaging.SingleEmailMessage> lstNotifications= new list<Messaging.SingleEmailMessage>();
            
            //list of Cases that failed sending Notifications due to the max number of recipients in BCC
            list<Case> lstFailedCases = new list<Case>();
            
            //Query on Email template 
            map<string ,ID> mapEmailTemplate = new map<string,ID>();
            for(EmailTemplate em : [select id,DeveloperName from EmailTemplate where DeveloperName like 'SRV%'])
            {
                mapEmailTemplate.put(em.DeveloperName,em.ID);
            }
            
            //Get the list of OrgEMail Addresses
            map<string, OrgWideEmailAddress> mapOrgWideEmails = new map<String, OrgWideEmailAddress>();
            for (OrgWideEmailAddress objOrgAddress : [select Id, DisplayName, Address from OrgWideEmailAddress])
            { 
                mapOrgWideEmails.put(objOrgAddress.DisplayName, objOrgAddress);
            }
            
            //Describe call to get the custom setting feild labels
            String strobjectName='SRV_Notification_Config__c';
            Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
            Schema.SObjectType CustomsettingSchema = schemaMap.get(strobjectName);
            Map<String, Schema.SObjectField> fieldMap = CustomsettingSchema.getDescribe().fields.getMap();
            
            Map<String, SRV_Notification_Config__c> MapNotifConfig = SRV_Notification_Config__c.getAll();
            Map<String, SRV_Email_To_Case_Config__c> MapEmailToCaseConfig = SRV_Email_To_Case_Config__c.getAll();
            
            //Loop thru the list of Cases
            for (Case objCase : lstCases)
            {
                //Based on Case Status, get the Template and Recipients List from map of Custom Settings
                SRV_Notification_Config__c NotificationConfigs = SRV_Notification_Config__c.getValues(objCase.Status);
                
                //Only if there is configuration defined for this case status in custom settings
                if (NotificationConfigs != null  && NotificationConfigs.Disable_Notification__c == false)
                {
                    //Get the Recipients List by Market Segment --CHANGE
                    String strRecipientsList = ''; //= NotificationConfigs.Recipients__c;
                    String strTORecipientsList = '';
                    String strBCCRecipientsList = '';
                    //system.debug('objCase.Market_Segment_HDN__c---'+objCase.Market_Segment_HDN__c);
                    //assigning recipients based on market segment
                    for (String fieldName: fieldMap.keySet()) {// list of all field API name;
                        //To check Market segment on timelog is same as Notification config field label
                        string CaseMarketSegment = objCase.Market_Segment__c;
                        string fieldlabel = fieldMap.get(fieldName).getDescribe().getLabel();

                        //To check Market segment on timelog is same as Notification config field label
                        if(fieldlabel.startsWith(CaseMarketSegment))
                        {
                            SRV_Notification_Config__c value = MapNotifConfig.get(objCase.Status);
                            strRecipientsList = (string)value.get(fieldName);
                            system.debug('fieldName--'+fieldName+ '---string)value.get(fieldName)----'+(string)value.get(fieldName));
                            if(fieldlabel.endsWith('To'))
                                strTORecipientsList = ((string)value.get(fieldName) !=null) ?(string)value.get(fieldName) : '';
                            else if(fieldlabel.endsWith('BCC'))
                                strBCCRecipientsList = ((string)value.get(fieldName) !=null) ?(string)value.get(fieldName) : '';
                            
                            //if contactEmail is a recipient, Throw an exception if the contact email was bounced earlier.  
                            
                            if (strTORecipientsList.contains('ContactEmail') )            
                            {
                                system.debug('Case Contact is' + objCase.ContactEmail);
                                if(objCase.ContactId == null || objCase.ContactEmail == null)
                                {
                                    throw new ApexException('Case has no contact or Email populated.');
                                }
                                else if(objCase.Contact.EmailBouncedDate != null)
                                {
                                    throw new ApexException('Contact Email is Bounced');
                                }
                            }
                        }
                    }
                     system.debug('strTORecipientsList---'+strTORecipientsList);
                    system.debug('strBCCRecipientsList---'+strBCCRecipientsList);
                    
                    //Proceed preparing email only if there are recipients
                    if (strBCCRecipientsList.length() > 0 || strTORecipientsList.length() >0)
                    {
                        //Adding To addresses to list                        
                        list<string> lstTODistribution = new list<string>();
                        if(strTORecipientsList != '')
                            lstTODistribution = ConvertRecipientsToList(strTORecipientsList, objCase);
                        system.debug('lstTODistribution---'+lstTODistribution);
                        
                        //Adding Bcc addresses to List
                        list<string> lstBCCDistribution = new list<string>();
                        if(strBCCRecipientsList != '')
                            lstBCCDistribution = ConvertRecipientsToList(strBCCRecipientsList, objCase);
                        system.debug('lstBCCDistribution--1-'+lstBCCDistribution);
                    
                        //Prepare the EmailInstance (modified to render data for vf email template)
                        Messaging.singleEmailMessage objEmailMsg = Messaging.renderStoredEmailTemplate(mapEmailTemplate.get(NotificationConfigs.Template_Name__c), userinfo.getUserId(), objCase.Id);
                        
                        //Check if the count of recipients is more than 25, as BCC can accept only 25
                        if ((!lstTODistribution.isempty())
                            || (!lstBCCDistribution.isempty() && lstBCCDistribution.size() <= 25))
                        {
                            objEmailMsg.setToAddresses(lstTODistribution);
                            if(lstBCCDistribution.size() <= 25)
                                objEmailMsg.setBccAddresses(lstBCCDistribution);
                            //Emailwithattch.setSenderDisplayName('GCI Support');
                            if(mapOrgWideEmails.get(NotificationConfigs.FromEmail__c) != null)
                                objEmailMsg.setOrgWideEmailAddressId(mapOrgWideEmails.get(NotificationConfigs.FromEmail__c).ID);
                            //if(mapOrgWideEmails.get(NotificationConfigs.ReplyToEmail__c) != null)
                                //objEmailMsg.setReplyTo(mapOrgWideEmails.get(NotificationConfigs.ReplyToEmail__c).Address);
                            
                            //Assigns Reply To email from custom setting based on the support team
                            string strSupportTeam = objCase.SRV_Support_Team__c;
                            if (strSupportTeam != '' && !MapEmailToCaseConfig.isempty())
                            {
                                 if (strSupportTeam.startsWith('BTS') && MapEmailToCaseConfig.get('BTS') != null)
                                    objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('BTS').Reply_To_Email__c);
                                else if (strSupportTeam.startsWith('IS') && MapEmailToCaseConfig.get('IS') != null)
                                    objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('IS').Reply_To_Email__c);
                                else if(strSupportTeam.startsWith('RMS') && MapEmailToCaseConfig.get('RMS') != null)
                                    objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('RMS').Reply_To_Email__c);
                            }
                            String emailSubject = objEmailMsg.getSubject();
                            String emailTextBody = objEmailMsg.getPlainTextBody();
                            String emailHTMLBody = objEmailMsg.getHtmlBody();
                            system.debug('emailHTMLBody--'+emailHTMLBody);
                            objEmailMsg.setSubject(emailSubject);
                            objEmailMsg.setPlainTextBody(emailTextBody);
                            objEmailMsg.setHtmlBody(emailHTMLBody);
                            
                            //commented objEmailMsg.setWhatId(objTimeLog.Id); 
                            objEmailMsg.setSaveAsActivity(True);
                            //objEmailMsg.setTreatTargetObjectAsRecipient(false);
                            //if(objCase.ContactId != null)
                            objEmailMsg.setTargetObjectId(objCase.ContactId);
                            //objEmailMsg.setTargetObjectId('0031g00000GMBeHAAX');
                            //commented objEmailMsg.setTemplateId(mapEmailTemplate.get(NotificationConfigs.Template_Name__c));
                            //Add it to the list
                            lstNotifications.add(objEmailMsg);
                        }else
                        { 
                            //Mark a flag on the timeLog that the message was not sent.
                            Case objFailedCase = new Case(id = objCase.Id);
                            objFailedCase.Notification_Failed__c = true;
                            lstFailedCases.add(objFailedCase);
                            
                        }
                    }
                    else
                    {
                        system.debug('Exception in SendCaseNotifications : No Recipients configured for this case status ' + objCase.Status);
                    }
                }else
                {
                    system.debug('Exception in SendCaseNotifications : No custom setting for the Case Status '+ objCase.Status);
                }
                
            }
            
            //Send Emails
            if (lstNotifications.size() >0)
            {
                Messaging.SendEmailResult [] EmailResult = Messaging.sendEmail(lstNotifications);
                system.debug('EmailResult---'+EmailResult);
                for(Messaging.SendEmailResult objResult : EmailResult)
                {
                    if(objResult.isSuccess()){}
                    else{
                        system.debug('Email Errors--'+objResult.getErrors());
                    }
                }
            }
            
            //Update the Cases that failed notifications
            if (lstFailedCases.size() > 0)
                update lstFailedCases;
        }
        Catch(exception ex)
        {
            system.debug('Exception in SendCaseNotifications :' + ex + ' at ' + ex.getLineNumber());
            throw new ApexException('Exception:' +ex.getMessage());
        }
    }
    
        //To split recipients list by comma and email fields 
    public static list<string> ConvertRecipientsToList(string RecipientList,Case objCase)
    {
        list<string> lstDistribution = new list<string>();
        list<id> lstUserIDs = new list<id>();
        //Prepare Recipients List into a List
            for (string strRecipientField : RecipientList.split(','))
        {
            String strDistributionList;
            //Recipient will be either a FieldName, Email Address
            //Add the logic to check the email address by finding @ -- CHANGE
            system.debug('strRecipientField---'+strRecipientField);
            //Check if it is an email address
            if(strRecipientField.contains('@'))
            {
                lstDistribution.add(strRecipientField);
            }else
            {
                //Get the value of recipient field value from TimeLog
                strDistributionList =  (String) objCase.get(strRecipientField.trim()) != '' ? (String) objCase.get(strRecipientField.trim()) : '';                                
            }
            
            if (strDistributionList!= null)
            {
                if (strDistributionList.startsWith('005')) //if it is a user
                {
                    lstUserIDs.add(strDistributionList);
                }else if (strDistributionList.contains(';'))
                    lstDistribution.addall(strDistributionList.split(';'));
                else
                    lstDistribution.addall(strDistributionList.split(','));
                
                system.debug('lstDistribution---'+lstDistribution+'---strDistributionList---'+strDistributionList);
            }
        }
         if (lstUserIDs.size() > 0)
             lstDistribution.addAll(lstUserIDs);
        return lstDistribution;
    }
    public class ApexException extends Exception {}
}